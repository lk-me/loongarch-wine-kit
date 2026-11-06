/* Minimal LoongArch64 CRT startup object for mingw-w64.

   This is a deliberately tiny replacement for the full mingw-w64 crt0:
   it only defines mainCRTStartup, the PE entry point that lld selects
   for a console subsystem image.  On a real Windows loader the entry
   point is invoked with a valid stack; returning from it hands the value
   in $a0 (the LoongArch return register) back to the loader, which uses
   it as the process exit code.

   Note: $ra must be preserved across the call to main.  Returning with
   the $ra left behind by "bl main" would jump back into this very
   function and spin forever.  */

    .text
    .globl mainCRTStartup
    .p2align 2
    .seh_proc mainCRTStartup
mainCRTStartup:
    addi.d $sp, $sp, -16
    .seh_stackalloc 16
    st.d   $ra, $sp, 8
    .seh_savereg $ra, 8
    .seh_endprologue
    bl     main
    ld.d   $ra, $sp, 8
    addi.d $sp, $sp, 16
    jr     $ra
    .seh_endproc
