package com.example.testsign;

/** Port of assets/modules/features.py; input landmarks use the unmirrored frame. */
public final class SignFeatures {
    private static final int[] HP = {0,1,2,3,0,5,6,7,0,9,10,11,0,13,14,15,0,17,18,19};
    private static final int[] HC = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20};
    private static final int[] UP = {1,1,2,3,1,5,6}, UC = {0,2,3,4,5,6,7};
    private SignFeatures() { }

    public static float[] extract(float[][] right, float[][] left, float[][] landmarks, int w, int h) {
        float[][] pose = new float[8][3];
        if (landmarks != null) {
            int[] indices = {0,11,12,14,16,11,13,15};
            for (int i=0;i<8;i++) pose[i] = pixel(landmarks[indices[i]], w, h);
            for (int j=0;j<3;j++) pose[1][j] = (pose[5][j]+pose[2][j])/2;
        }
        float[] neck = pose[1].clone();
        double width = 0;
        for (int j=0;j<3;j++) width += Math.pow(pose[5][j]-pose[2][j],2);
        float scale = (float)Math.sqrt(width);
        if (scale<1e-6f) scale=1;
        normalize(pose,neck,scale);
        float[][] rh = new float[21][3], lh = new float[21][3];
        if (right!=null) {
            for (int i=0;i<21;i++) rh[i]=pixel(right[i],w,h);
            normalize(rh,neck,scale);
        }
        if (left!=null) {
            for (int i=0;i<21;i++) lh[i]=pixel(left[i],w,h);
            normalize(lh,neck,scale);
        }
        float[] out=new float[150];
        geometry(rh,HP,HC,new int[]{0,4,8},new int[]{1,5,9},out,0);
        geometry(lh,HP,HC,new int[]{0,4,8},new int[]{1,5,9},out,63);
        geometry(pose,UP,UC,new int[]{2,5,1},new int[]{3,6,4},out,126);
        for (float value:out) if (!Float.isFinite(value)) throw new IllegalArgumentException("Invalid landmarks");
        return out;
    }
    private static float[] pixel(float[] p,int w,int h) { return new float[]{p[0]*w,p[1]*h,p[2]*w}; }
    private static void normalize(float[][] coords,float[] neck,float scale) {
        for (float[] p:coords) for (int j=0;j<3;j++) p[j]=(p[j]-neck[j])/scale;
    }
    private static void geometry(float[][] coords,int[] parents,int[] children,int[] a,int[] b,float[] out,int offset) {
        boolean empty=true;
        for (float[] p:coords) for(float v:p) if(v!=0) empty=false;
        if(empty) return;
        int n=parents.length;
        float[][] bones=new float[n][3];
        for(int i=0;i<n;i++) {
            for(int j=0;j<3;j++) bones[i][j]=coords[children[i]][j]-coords[parents[i]][j];
            double norm=Math.hypot(bones[i][0],bones[i][1])+1e-6;
            out[offset+i]=(float)(bones[i][0]/norm);
            out[offset+n+i]=(float)(bones[i][1]/norm);
            out[offset+2*n+i]=bones[i][2];
        }
        for(int i=0;i<a.length;i++) {
            float[] v=bones[a[i]],u=bones[b[i]];
            double dot=(double)v[0]*u[0]+(double)v[1]*u[1];
            double denom=Math.hypot(v[0],v[1])*Math.hypot(u[0],u[1])+1e-6;
            out[offset+3*n+i]=(float)Math.acos(Math.max(-1,Math.min(1,dot/denom)));
        }
    }
}
