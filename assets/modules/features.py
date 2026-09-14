import numpy as np

H_PARENTS = [0, 1, 2, 3, 0, 5, 6, 7, 0, 9, 10, 11, 0, 13, 14, 15, 0, 17, 18, 19]
H_CHILDREN = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
UB_PARENTS = [1, 1, 2, 3, 1, 5, 6]
UB_CHILDREN = [0, 2, 3, 4, 5, 6, 7]

def compute_25d_features(coords, parents, children, angle_v1, angle_v2):
    """
    Computes decoupled 2.5D geometric features: 2D direction vectors, Z-depths, and internal angles.
    Returns a concatenated 1D float32 array.
    """
    coords = np.array(coords, dtype=np.float32)
    if coords.sum() == 0:
        return np.zeros((len(parents)*3 + len(angle_v1)), dtype=np.float32)
    
    p_coords = coords[parents]
    c_coords = coords[children]
    bones = c_coords - p_coords
    
    dx = bones[:, 0]
    dy = bones[:, 1]
    dz = bones[:, 2]
    
    norm2d = np.sqrt(dx**2 + dy**2) + 1e-6
    u_x = dx / norm2d
    u_y = dy / norm2d
    z_feat = dz
    
    v1 = bones[angle_v1, :2]
    v2 = bones[angle_v2, :2]
    dot = np.sum(v1 * v2, axis=1)
    n1 = np.linalg.norm(v1, axis=1)
    n2 = np.linalg.norm(v2, axis=1)
    denom = n1 * n2 + 1e-6
    angles = np.arccos(np.clip(dot / denom, -1.0, 1.0))
    
    return np.concatenate([u_x, u_y, z_feat, angles])

def extract_keypoints(results, w, h):
    """
    Extracts Mediapipe pose and hand results into a standardized 150D feature vector.
    Normalizes scale based on shoulder width.
    """
    try:
        pose = np.zeros((8, 3), dtype=np.float32)
        if results.pose_landmarks:
            plm = results.pose_landmarks.landmark
            pose[0] = [plm[0].x * w, plm[0].y * h, plm[0].z * w]
            l_sh = np.array([plm[11].x * w, plm[11].y * h, plm[11].z * w])
            r_sh = np.array([plm[12].x * w, plm[12].y * h, plm[12].z * w])
            pose[1] = (l_sh + r_sh) / 2.0
            pose[2] = r_sh
            pose[3] = [plm[14].x * w, plm[14].y * h, plm[14].z * w]
            pose[4] = [plm[16].x * w, plm[16].y * h, plm[16].z * w]
            pose[5] = l_sh
            pose[6] = [plm[13].x * w, plm[13].y * h, plm[13].z * w]
            pose[7] = [plm[15].x * w, plm[15].y * h, plm[15].z * w]
            
        rh = np.zeros((21, 3), dtype=np.float32)
        if results.right_hand_landmarks:
            for i, lm in enumerate(results.right_hand_landmarks.landmark):
                rh[i] = [lm.x * w, lm.y * h, lm.z * w]
                
        lh = np.zeros((21, 3), dtype=np.float32)
        if results.left_hand_landmarks:
            for i, lm in enumerate(results.left_hand_landmarks.landmark):
                lh[i] = [lm.x * w, lm.y * h, lm.z * w]
                
        neck = pose[1].copy()
        pose -= neck
        if results.right_hand_landmarks: rh -= neck
        if results.left_hand_landmarks: lh -= neck
            
        swidth = np.linalg.norm(pose[5] - pose[2])
        if swidth < 1e-6: swidth = 1.0
            
        pose /= swidth
        if results.right_hand_landmarks: rh /= swidth
        if results.left_hand_landmarks: lh /= swidth
            
        r_feat = compute_25d_features(rh, H_PARENTS, H_CHILDREN, [0, 4, 8], [1, 5, 9])
        l_feat = compute_25d_features(lh, H_PARENTS, H_CHILDREN, [0, 4, 8], [1, 5, 9])
        ub_feat = compute_25d_features(pose, UB_PARENTS, UB_CHILDREN, [2, 5, 1], [3, 6, 4])
        
        return np.concatenate([r_feat, l_feat, ub_feat])
    except Exception:
        return np.zeros((150,), dtype=np.float32)
