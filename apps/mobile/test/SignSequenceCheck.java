package com.example.testsign;

public final class SignSequenceCheck {
    private static void check(boolean value) {
        if (!value) throw new AssertionError("Sequence regression");
    }
    public static void main(String[] args) {
        SignSequence sequence=new SignSequence();
        float[] frame=new float[150];
        for (int i=0;i<29;i++) {
            check(sequence.add(frame,i*1200,true,true)==null);
            check(sequence.size()==i+1);
        }
        check(sequence.add(frame,29*1200,true,true).length==13560);
        check(sequence.add(frame,29*1200+100,true,true)==null);
        check(sequence.add(frame,29*1200+499,true,true)==null);
        check(sequence.add(frame,29*1200+500,true,true).length==13560);
        check(sequence.size()==30);
        sequence.reset();
        check(sequence.size()==0);
        sequence.add(frame,0,true,true);
        sequence.missing(100);
        sequence.add(frame,700,true,true);
        check(sequence.size()==2);
        sequence.missing(800);
        sequence.missing(2300);
        check(sequence.size()==0);
        sequence.add(frame,2400,true,true);
        sequence.missing(2500);
        sequence.add(frame,4500,true,true);
        check(sequence.size()==1);
        System.out.println("Java sequence passed: slow frames, brief/sustained loss, throttle, reset");
    }
}
