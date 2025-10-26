import torch
import cv2
import numpy as np
import time
import threading
import queue
from ultralytics import YOLO
from gtts import gTTS
import pygame
import os
import tempfile
import hashlib


# ----------------------------
# Tracker & Mental Map
# ----------------------------
class SimpleTracker:
    def __init__(self, iou_threshold=0.3, max_age=30):
        self.next_id = 0
        self.boxes_2d = {}
        self.positions_3d = {}
        self.timestamps = {}
        self.ages = {}
        self.iou_threshold = iou_threshold
        self.max_age = max_age

    def iou(self, boxA, boxB):
        xA = max(boxA[0], boxB[0])
        yA = max(boxA[1], boxB[1])
        xB = min(boxA[2], boxB[2])
        yB = min(boxA[3], boxB[3])
        interArea = max(0, xB - xA) * max(0, yB - yA)
        boxAArea = max(0, boxA[2]-boxA[0]) * max(0, boxA[3]-boxA[1])
        boxBArea = max(0, boxB[2]-boxB[0]) * max(0, boxB[3]-boxB[1])
        unionArea = boxAArea + boxBArea - interArea
        if unionArea <= 0:
            return 0.0
        return interArea / float(unionArea + 1e-6)

    def assign_ids(self, detections, current_frame):
        assigned = []
        used_ids = set()

        for det in detections:
            det_bbox = list(det["bbox"])
            det_pos3d = np.array(det["3D_position"])
            matched_id = None
            best_iou = 0

            for obj_id, prev_box in self.boxes_2d.items():
                if obj_id in used_ids:
                    continue
                iou_score = self.iou(det_bbox, prev_box)
                if iou_score > self.iou_threshold and iou_score > best_iou:
                    matched_id = obj_id
                    best_iou = iou_score

            if matched_id is None:
                matched_id = self.next_id
                self.next_id += 1
            
            used_ids.add(matched_id)

            prev_pos3d = self.positions_3d.get(matched_id)
            prev_time = self.timestamps.get(matched_id, current_frame)
            dt = max(current_frame - prev_time, 1)
            
            if prev_pos3d is not None and dt > 0:
                velocity = (det_pos3d - np.array(prev_pos3d)) / dt
            else:
                velocity = np.zeros(3)

            self.boxes_2d[matched_id] = det_bbox
            self.positions_3d[matched_id] = det_pos3d
            self.timestamps[matched_id] = current_frame
            self.ages[matched_id] = 0

            det["velocity"] = velocity
            assigned.append((matched_id, det))

        for obj_id in list(self.ages.keys()):
            if obj_id not in used_ids:
                self.ages[obj_id] += 1

        active_ids = [oid for oid, age in self.ages.items() if age <= self.max_age]
        self.boxes_2d = {oid: self.boxes_2d[oid] for oid in active_ids if oid in self.boxes_2d}
        self.positions_3d = {oid: self.positions_3d[oid] for oid in active_ids if oid in self.positions_3d}
        self.timestamps = {oid: self.timestamps[oid] for oid in active_ids if oid in self.timestamps}
        self.ages = {oid: self.ages[oid] for oid in active_ids}

        return assigned


class MentalMap3D:
    def __init__(self, keep_seconds=5.0):
        self.map = {}
        self.keep_seconds = keep_seconds

    def update(self, tracked_objects):
        current_time = time.time()
        for obj_id, det in tracked_objects:
            self.map[obj_id] = {
                "class": det["class"],
                "position": det["3D_position"],
                "velocity": det["velocity"],
                "last_seen": current_time
            }
        self.map = {oid: info for oid, info in self.map.items()
                    if current_time - info["last_seen"] <= self.keep_seconds}


# ----------------------------
# Depth Estimation
# ----------------------------
def load_midas_model():
    print("Loading MiDaS model...")
    midas = torch.hub.load("intel-isl/MiDaS", "MiDaS_small")
    midas.eval()
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    midas.to(device)
    transforms = torch.hub.load("intel-isl/MiDaS", "transforms")
    midas_transform = transforms.small_transform
    print(f"MiDaS loaded on {device}")
    return midas, midas_transform, device


def estimate_depth(frame, midas, midas_transform, device):
    img = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    input_batch = midas_transform(img).to(device)
    with torch.no_grad():
        prediction = midas(input_batch)
        prediction = torch.nn.functional.interpolate(
            prediction.unsqueeze(1),
            size=img.shape[:2],
            mode="bicubic",
            align_corners=False
        ).squeeze()
    depth = prediction.cpu().numpy()
    depth = (depth - depth.min()) / (depth.max() - depth.min() + 1e-6)
    depth = 0.5 + depth * 9.5
    return depth


def visualize_depth_map(depth_map):
    """Convert depth map to colored visualization."""
    # Normalize to 0-255
    depth_normalized = ((depth_map - depth_map.min()) / 
                       (depth_map.max() - depth_map.min() + 1e-6) * 255).astype(np.uint8)
    
    # Apply colormap (TURBO for better visibility)
    depth_colored = cv2.applyColorMap(depth_normalized, cv2.COLORMAP_TURBO)
    
    return depth_colored


# ----------------------------
# 3D Position Computation
# ----------------------------
def compute_3d_position(bbox, depth_map, intrinsics):
    x_center = int((bbox[0]+bbox[2])/2)
    y_center = int((bbox[1]+bbox[3])/2)
    h, w = depth_map.shape
    x_center = np.clip(x_center, 0, w-1)
    y_center = np.clip(y_center, 0, h-1)
    depth = depth_map[y_center, x_center]
    fx, fy = intrinsics['fx'], intrinsics['fy']
    cx, cy = intrinsics['cx'], intrinsics['cy']
    X = (x_center - cx) * depth / fx
    Y = (y_center - cy) * depth / fy
    Z = depth
    return [X, Y, Z]


# ----------------------------
# Semantic Prioritization Engine
# ----------------------------
def prioritize_objects(mental_map, user_forward=(0,0,1), top_n=5):
    """Rank objects by urgency, proximity, and relevance."""
    scored_objects = []
    
    for obj_id, info in mental_map.items():
        pos = np.array(info['position'])
        vel = np.array(info['velocity'])
        distance = np.linalg.norm(pos)
        
        type_score = {
            "person": 5, "car": 6, "truck": 6, "bus": 6,
            "bicycle": 4, "motorcycle": 5, "traffic light": 3,
            "stop sign": 4, "bench": 2, "chair": 2,
            "dog": 4, "cat": 3
        }.get(info['class'], 2)
        
        velocity_magnitude = np.linalg.norm(vel)
        velocity_score = max(0, -vel[2]) if velocity_magnitude > 0.01 else 0
        fov_angle = np.arctan2(abs(pos[0]), max(pos[2], 0.1))
        fov_factor = 1.0 if fov_angle < np.pi/4 else 0.5
        urgency = 1.0 if distance < 2.0 else 0.5
        
        score = (0.3*type_score + 0.3*(1/(distance+0.5)) + 
                 0.2*velocity_score + 0.2*urgency) * fov_factor
        
        scored_objects.append((score, obj_id, info))
    
    scored_objects.sort(reverse=True, key=lambda x: x[0])
    return [(oid, info) for _, oid, info in scored_objects[:top_n]]


# ----------------------------
# Contextual Situation Analysis
# ----------------------------
def analyze_situation(mental_map, prioritized_objects):
    situation = {
        "urgent_alerts": [],
        "path_status": "clear",
        "obstacles": [],
        "moving_objects": []
    }
    
    for obj_id, info in mental_map.items():
        pos = np.array(info['position'])
        vel = np.array(info['velocity'])
        cls = info['class']
        distance = np.linalg.norm(pos)
        
        x = pos[0]
        if x < -0.5:
            direction = "left"
        elif x > 0.5:
            direction = "right"
        else:
            direction = "ahead"
        
        velocity_magnitude = np.linalg.norm(vel)
        is_moving = velocity_magnitude > 0.05
        is_approaching = vel[2] < -0.02 if is_moving else False
        
        if is_approaching and distance < 3.0:
            if distance < 1.5:
                urgency = "very close"
            elif distance < 2.5:
                urgency = "approaching quickly"
            else:
                urgency = "approaching"
            
            situation["urgent_alerts"].append({
                "object": cls,
                "direction": direction,
                "urgency": urgency,
                "distance": distance
            })
        
        elif is_moving and distance < 4.0:
            situation["moving_objects"].append({
                "object": cls,
                "direction": direction,
                "distance": distance
            })
        
        elif not is_moving and direction == "ahead" and distance < 3.0:
            situation["obstacles"].append({
                "object": cls,
                "distance": distance
            })
    
    ahead_clear = True
    for obj_id, info in mental_map.items():
        pos = np.array(info['position'])
        x, z = pos[0], pos[2]
        distance = np.linalg.norm(pos)
        
        if abs(x) < 0.7 and z > 0 and distance < 3.0:
            ahead_clear = False
            break
    
    situation["path_status"] = "clear" if ahead_clear else "blocked"
    return situation


def generate_contextual_narration(situation, prioritized_objects):
    narration_parts = []
    
    if situation["urgent_alerts"]:
        for alert in situation["urgent_alerts"][:2]:
            obj = alert["object"]
            direction = alert["direction"]
            urgency = alert["urgency"]
            
            if urgency == "very close":
                narration_parts.append(f"{obj} {urgency} on your {direction}")
            else:
                narration_parts.append(f"{obj} {urgency} from your {direction}")
    
    elif situation["moving_objects"]:
        for mov in situation["moving_objects"][:2]:
            obj = mov["object"]
            direction = mov["direction"]
            narration_parts.append(f"{obj} moving on your {direction}")
    
    elif situation["obstacles"]:
        for obs in situation["obstacles"][:1]:
            obj = obs["object"]
            narration_parts.append(f"{obj} in path ahead")
    
    if situation["path_status"] == "clear":
        narration_parts.append("the way ahead is clear")
    else:
        narration_parts.append("obstacle in path")
    
    if not narration_parts or len(narration_parts) == 1:
        return "Path is clear, no immediate hazards"
    
    if len(narration_parts) == 1:
        return narration_parts[0]
    else:
        return "; ".join(narration_parts[:2])


# ----------------------------
# Intelligent TTS Engine
# ----------------------------
class IntelligentTTSEngine:
    def __init__(self, speed=1.3):
        base_frequency = 22050
        adjusted_frequency = int(base_frequency * speed)
        pygame.mixer.init(frequency=adjusted_frequency, size=-16, channels=2, buffer=512)

        self.cache_dir = tempfile.mkdtemp()
        self.phrase_q = queue.Queue(maxsize=5)
        self.running = True
        self.last_narration = ""
        self.last_narration_time = 0
        self.phrases_spoken = 0
        
        self.worker = threading.Thread(target=self._worker_loop, daemon=True)
        self.worker.start()
        print(f"Intelligent TTS at {speed}x speed. Cache: {self.cache_dir}")

    def _cache_path(self, text):
        h = hashlib.md5(text.encode()).hexdigest()
        return os.path.join(self.cache_dir, f"{h}.mp3")

    def speak(self, text, force=False):
        if not text:
            return
        
        if not force:
            if text == self.last_narration:
                time_since = time.time() - self.last_narration_time
                if time_since < 3.0:
                    return
        
        self.last_narration = text
        self.last_narration_time = time.time()
        
        try:
            if self.phrase_q.full():
                try:
                    self.phrase_q.get_nowait()
                except queue.Empty:
                    pass
            
            self.phrase_q.put_nowait(text)
        except queue.Full:
            pass

    def _ensure_audio(self, text):
        path = self._cache_path(text)
        if not os.path.exists(path):
            tts = gTTS(text=text, lang='en', slow=False)
            tts.save(path)
        return path

    def _play_path(self, path):
        pygame.mixer.music.load(path)
        pygame.mixer.music.play()
        while pygame.mixer.music.get_busy():
            time.sleep(0.01)

    def _worker_loop(self):
        while self.running:
            try:
                text = self.phrase_q.get(timeout=0.2)
            except queue.Empty:
                continue
            
            try:
                path = self._ensure_audio(text)
                self._play_path(path)
                self.phrases_spoken += 1
            except Exception as e:
                print(f"[TTS] Error: {e}")

    def stop(self):
        self.running = False
        while not self.phrase_q.empty():
            try:
                self.phrase_q.get_nowait()
            except queue.Empty:
                break
        try:
            pygame.mixer.music.stop()
            pygame.mixer.quit()
        except:
            pass
        try:
            for f in os.listdir(self.cache_dir):
                try:
                    os.remove(os.path.join(self.cache_dir, f))
                except:
                    pass
            os.rmdir(self.cache_dir)
        except:
            pass
        print(f"TTS stopped. Narrations spoken: {self.phrases_spoken}")


# ----------------------------
# Main Loop with Dual Display
# ----------------------------
if __name__ == "__main__":
    camera_intrinsics = {"fx": 224, "fy": 224, "cx": 112, "cy": 112}

    print("="*60)
    print("AI-POWERED ASSISTIVE NAVIGATION SYSTEM")
    print("DUAL VIEW: DETECTION + DEPTH MAP")
    print("="*60)
    
    print("\n[1/4] Loading YOLO model...")
    yolo_model = YOLO("yolo11n.pt")
    print("✓ YOLO loaded")
    
    print("\n[2/4] Loading MiDaS depth model...")
    midas, midas_transform, device = load_midas_model()
    print("✓ MiDaS loaded")
    
    print("\n[3/4] Initializing tracker and mental map...")
    tracker = SimpleTracker()
    mental_map = MentalMap3D()
    print("✓ Tracker initialized")
    
    print("\n[4/4] Initializing intelligent TTS engine...")
    tts = IntelligentTTSEngine(speed=1.3)
    print("✓ TTS initialized")
    
    print("\n" + "="*60)
    print("Starting camera feed...")
    print("Press 'q' to quit")
    print("="*60 + "\n")
    
    # Mobile camera connection
    # mobile_ip = "http://192.168.127.180:8080/video"
    # cap = cv2.VideoCapture(mobile_ip)
    # cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    cap = cv2.VideoCapture(0)  # 0 = default laptop webcam
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    
    if not cap.isOpened():
        print("❌ Error: Cannot connect to camera")
        exit()
    
    frame_count = 0
    depth_map = None
    last_narration_frame = 0
    narration_interval = 45

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                print("❌ Failed to grab frame")
                break
            
            frame_resized = cv2.resize(frame, (224, 224))
            frame_count += 1

            # Update depth every 3 frames
            if frame_count % 3 == 0:
                depth_map = estimate_depth(frame_resized, midas, midas_transform, device)
            
            if depth_map is None:
                continue

            # YOLO detection
            results = yolo_model(frame_resized, verbose=False)
            detections_3d = []
            
            for r in results:
                if r.boxes is None or len(r.boxes) == 0:
                    continue
                    
                boxes = r.boxes.xyxy.cpu().numpy()
                classes = r.boxes.cls.cpu().numpy()
                
                for i in range(len(boxes)):
                    bbox = boxes[i]
                    cls_idx = int(classes[i])
                    class_name = r.names[cls_idx]
                    
                    det = {
                        "bbox": bbox, 
                        "class": class_name,
                        "3D_position": compute_3d_position(bbox, depth_map, camera_intrinsics)
                    }
                    detections_3d.append(det)

            # Track objects
            tracked_objects = tracker.assign_ids(detections_3d, frame_count)
            mental_map.update(tracked_objects)
            
            # Prioritize objects
            prioritized = prioritize_objects(mental_map.map)

            # Generate contextual narration
            if frame_count - last_narration_frame >= narration_interval:
                situation = analyze_situation(mental_map.map, prioritized)
                narration = generate_contextual_narration(situation, prioritized)
                tts.speak(narration)
                print(f"\n[Narration] {narration}\n")
                last_narration_frame = frame_count

            # ===== VISUALIZATION - DETECTION FRAME =====
            vis_frame = frame_resized.copy()
            
            # Draw all detections
            for det in detections_3d:
                x1, y1, x2, y2 = map(int, det["bbox"])
                cv2.rectangle(vis_frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
                pos = det["3D_position"]
                dist = np.linalg.norm(pos)
                label = f"{det['class']} {dist:.1f}m"
                cv2.putText(vis_frame, label, (x1, y1-5),
                           cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 255, 0), 1)
            
            # Highlight prioritized objects
            for obj_id, info in prioritized:
                for oid, det in tracked_objects:
                    if oid == obj_id:
                        x1, y1, x2, y2 = map(int, det["bbox"])
                        cv2.rectangle(vis_frame, (x1, y1), (x2, y2), (0, 0, 255), 3)
                        break

            # Display info overlay
            cv2.putText(vis_frame, f"Frame: {frame_count} | Narrations: {tts.phrases_spoken}", 
                       (5, 15), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)
            cv2.putText(vis_frame, f"Objects: {len(detections_3d)} | Prioritized: {len(prioritized)}", 
                       (5, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)

            # ===== VISUALIZATION - DEPTH MAP =====
            depth_colored = visualize_depth_map(depth_map)
            
            # Add depth scale info
            cv2.putText(depth_colored, "DEPTH MAP", 
                       (5, 15), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 2)
            cv2.putText(depth_colored, "Red=Close | Blue=Far", 
                       (5, 35), cv2.FONT_HERSHEY_SIMPLEX, 0.35, (255, 255, 255), 1)

            # ===== COMBINE SIDE-BY-SIDE =====
            combined_view = np.hstack([vis_frame, depth_colored])
            
            # Add separator line
            h, w = combined_view.shape[:2]
            cv2.line(combined_view, (224, 0), (224, h), (255, 255, 255), 2)

            # Display combined view
            cv2.imshow("Navigation System - Detection | Depth", combined_view)
            
            if cv2.waitKey(1) & 0xFF == ord('q'):
                print("\n\nQuitting...")
                break

    except KeyboardInterrupt:
        print("\n\n⚠ Interrupted by user")
    except Exception as e:
        print(f"\n\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        print("\nCleaning up...")
        tts.stop()
        cap.release()
        cv2.destroyAllWindows() 
        print("✓ Cleanup complete")
        print("\nGoodbye! 👋\n")
