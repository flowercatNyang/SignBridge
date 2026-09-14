import com.example.testsign.SignFeatures;
import java.io.*;

/** Cross-language fixture check, launched by tools/check_sign_java.py. */
public class SignFeaturesCheck {
    private static float[][] points(DataInputStream in,int n) throws IOException {
        if (!in.readBoolean()) return null;
        float[][] p=new float[n][3];
        for(int i=0;i<n;i++) for(int j=0;j<3;j++) p[i][j]=in.readFloat();
        return p;
    }
    public static void main(String[] args) throws Exception {
        try(DataInputStream in=new DataInputStream(new FileInputStream(args[0]))) {
            int count=in.readInt(); float maxError=0;
            for(int c=0;c<count;c++) {
                int w=in.readInt(),h=in.readInt();
                float[] actual=SignFeatures.extract(points(in,21),points(in,21),points(in,33),w,h);
                for(int i=0;i<150;i++) {
                    float error=Math.abs(actual[i]-in.readFloat());
                    maxError=Math.max(maxError,error);
                    if(error>1e-4f) throw new AssertionError("Case "+c+", feature "+i+": "+error);
                }
            }
            System.out.println(count+" Java/Python feature cases passed; max error="+maxError);
        }
    }
}
