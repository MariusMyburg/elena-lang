// --- Predefined References  --
define GC_ALLOC	            10001h
define HOOK                 10010h
define INIT_RND             10012h
define INIT                 10013h
define NEWFRAME             10014h
define INIT_ET              10015h
define ENDFRAME             10016h
define RESTORE_ET           10017h
define OPENFRAME            10019h
define CLOSEFRAME           1001Ah
define NEWTHREAD            1001Bh
define CLOSETHREAD          1001Ch
define EXIT                 1001Dh
define CALC_SIZE            1001Fh
define GET_COUNT            10020h
define THREAD_WAIT          10021h
define NEW_HEAP             10025h
define BREAK                10026h
define EXPAND_HEAP          10028h
define NEW_EVENT            10101h

define CORE_GC_TABLE        20002h
define CORE_GC_SIZE         20003h
define CORE_STAT_COUNT      20004h
define CORE_STATICROOT      20005h
define CORE_TLS_INDEX       20007h
define THREAD_TABLE         20008h
define CORE_OS_TABLE        20009h
define CORE_MESSAGE_TABLE   2000Ah
define CORE_ET_TABLE        2000Bh

// GC TABLE OFFSETS
define gc_header             0000h
define gc_start              0004h
define gc_yg_start           0008h
define gc_yg_current         000Ch
define gc_yg_end             0010h
define gc_shadow             0014h
define gc_shadow_end         0018h
define gc_mg_start           001Ch
define gc_mg_current         0020h
define gc_end                0024h
define gc_mg_wbar            0028h
define gc_et_current         002Ch 
define gc_ext_stack_frame    0030h 
define gc_lock               0034h 
define gc_signal             0038h 
define tt_ptr                003Ch 
define tt_lock               0040h 

// GCXT TLS TABLE
define tls_stack_frame       0000h
define tls_stack_bottom      0004h
define tls_catch_addr        0008h
define tls_catch_level       000Ch
define tls_catch_frame       0010h
define tls_sync_event        0014h
define tls_flags             0018h

// Page Size
define page_size               10h
define page_size_order          4h
define page_size_order_minus2   2h
define page_mask        0FFFFFFF0h
define page_ceil               17h
define struct_mask         800000h

// Object header fields
define elObjectOffset        0008h
define elSyncOffset          0008h
define elSizeOffset          0008h
define elVMTOffset           0004h 
define elVMTFlagOffset       0008h
define elVMTSizeOffset       000Ch
define elPackageOffset       0010h

define page_align_mask   000FFFF0h

define SUBJ_MASK          1FFFFFFh                          

// --- GC_ALLOC ---
// in: ecx - counter ; ebx - size ; ecx - actual size ; out: eax - created object ; edi contains the object or zero
procedure %GC_ALLOC

  // ; GCXT: set lock
labStart:
  mov  esi, data : %CORE_GC_TABLE + gc_lock
labWait:
  mov edx, 1
  xor eax, eax
  lock cmpxchg dword ptr[esi], edx
  jnz  short labWait

  mov  eax, [data : %CORE_GC_TABLE + gc_yg_current]
  mov  edx, [data : %CORE_GC_TABLE + gc_yg_end]
  add  ecx, eax
  cmp  ecx, edx
  jae  short labYGCollect
  mov  [eax], ebx
  mov  [data : %CORE_GC_TABLE + gc_yg_current], ecx
  
  // ; GCXT: clear sync field
  mov  edx, 0FFFFFFFFh
  lea  eax, [eax + elObjectOffset]
  
  // ; GCXT: free lock
  // ; could we use mov [esi], 0 instead?
  lock xadd [esi], edx

  ret

labYGCollect:
  // ; restore ecx
  sub  ecx, eax

  // ; GCXT: find the current thread entry
  mov  edx, fs:[2Ch]
  mov  eax, [data : %CORE_TLS_INDEX]

  // ; GCXT: save registers
  push edi
  mov  eax, [edx+eax*4]
  push ebp
  
  // ; GCXT: lock stack frame
  // ; get current thread event
  mov  esi, [eax + tls_sync_event]         
  mov  [eax + tls_stack_frame], esp
  
  push ecx
  push ebx

  // ; === GCXT: safe point ===
  mov  edx, [data : %CORE_GC_TABLE + gc_signal]
  // ; if it is a collecting thread, starts the GC
  test edx, edx                       
  jz   short labConinue
  // ; otherwise eax contains the collecting thread event

  // ; signal the collecting thread that it is stopped
  push 0FFFFFFFFh // -1
  mov  edi, data : %CORE_GC_TABLE + gc_lock
  push edx
  push esi

  // ; signal the collecting thread that it is stopped
  call extern 'dlls'kernel32.SetEvent

  // ; free lock
  // ; could we use mov [esi], 0 instead?
  mov  ebx, 0FFFFFFFFh
  lock xadd [edi], ebx

  // ; stop until GC is ended
  call extern 'dlls'kernel32.WaitForSingleObject

  // ; restore registers and try again
  pop  ebx
  pop  ecx
  pop  ebp
  pop  edi

  jmp  labStart

labConinue:

  mov  [data : %CORE_GC_TABLE + gc_signal], esi // set the collecting thread signal
  mov  ebp, esp

  // ; === thread synchronization ===

  // ; create list of threads need to be stopped
  mov  eax, esi
  mov  edi, [data : %CORE_GC_TABLE + tt_ptr]
  // ; get tls entry address  
  mov  esi, data : %THREAD_TABLE
labNext:
  mov  edx, [esi]
  cmp  eax, [edx + tls_sync_event]
  setz cl
  or  ecx, [edx + tls_flags]
  test ecx, 1
  // ; skip current thread signal / thread in safe region from wait list
  jnz  short labSkipSave
  push [edx + tls_sync_event]
labSkipSave:

  // ; reset all signal events
  push [edx + tls_sync_event]
  call extern 'dlls'kernel32.ResetEvent      

  lea  esi, [esi+4]
  mov  eax, [data : %CORE_GC_TABLE + gc_signal]
  sub  edi, 1
  jnz  short labNext

  mov  esi, data : %CORE_GC_TABLE + gc_lock
  mov  edx, 0FFFFFFFFh
  mov  ebx, ebp

  // ; free lock
  // ; could we use mov [esi], 0 instead?
  lock xadd [esi], edx

  mov  ecx, esp
  sub  ebx, esp
  jz   short labSkipWait

  // ; wait until they all stopped
  push 0FFFFFFFFh // -1
  shr  ebx, 2
  push 0FFFFFFFFh // -1
  push ecx
  push ebx
  call extern 'dlls'kernel32.WaitForMultipleObjects

labSkipWait:
  // ; remove list
  mov  esp, ebp     

  // ==== GCXT end ==============
  
  // ; create set of roots
  mov  ebp, esp
  xor  ecx, ecx
  push ecx
  push ecx
  push ecx                                                              

  // ; save static roots
  mov  esi, data : %CORE_STATICROOT
  mov  ecx, [data : %CORE_STAT_COUNT]
  push esi
  push ecx

  // ; == GCXT: save frames ==
  mov  ebx, [data : %CORE_GC_TABLE + tt_ptr]

labYGNextThread:  
  sub  ebx, 1
  mov  eax, data : %THREAD_TABLE
  
  // ; get tls entry address
  mov  esi, [eax+ebx*4]            
  // ; get the top frame pointer
  mov  eax, [esi + tls_stack_frame]
  mov  ecx, eax

labYGNextFrame:
  mov  esi, eax
  mov  eax, [esi]
  test eax, eax
  jnz  short labYGNextFrame
  
  push ecx
  sub  ecx, esi
  neg  ecx
  push ecx  
  
  mov  eax, [esi + 4]
  test eax, eax
  mov  ecx, eax
  jnz  short labYGNextFrame
  nop
  nop
  test ebx, ebx
  jnz  short labYGNextThread
  // ; == GCXT: end ==
  
  // === Minor collection ===
  mov [ebp-4], esp

  // ; save mg -> yg roots 
  mov  ebx, [data : %CORE_GC_TABLE + gc_mg_current]
  mov  edi, [data : %CORE_GC_TABLE + gc_mg_start]
  sub  ebx, edi                                        // ; we need to check only MG region
  jz   labWBEnd                                        // ; skip if it is zero
  mov  esi, [data : %CORE_GC_TABLE + gc_mg_wbar]
  shr  ebx, page_size_order
  // ; lea  edi, [edi + elObjectOffset]

labWBNext:
  cmp  [esi], 0
  lea  esi, [esi+4]
  jnz  short labWBMark
  sub  ebx, 4
  ja   short labWBNext
  nop
  nop
  jmp  short labWBEnd

labWBMark:
  lea  eax, [esi-4]
  sub  eax, [data : %CORE_GC_TABLE + gc_mg_wbar]
  mov  edx, [esi-4]
  shl  eax, page_size_order
  lea  eax, [edi + eax + elObjectOffset]
  
  test edx, 0FFh
  jz   short labWBMark2
  mov  ecx, [eax-elSizeOffset]
  push eax
  and  ecx, 0FFFFFh
  push ecx

labWBMark2:
  lea  eax, [eax + page_size]
  test edx, 0FF00h
  jz   short labWBMark3
  mov  ecx, [eax-elSizeOffset]
  push eax
  and  ecx, 0FFFFFh
  push ecx

labWBMark3:
  lea  eax, [eax + page_size]
  test edx, 0FF0000h
  jz   short labWBMark4
  mov  ecx, [eax-elSizeOffset]
  push eax
  and  ecx, 0FFFFFh
  push ecx

labWBMark4:
  lea  eax, [eax + page_size]
  test edx, 0FF000000h
  jz   short labWBNext
  mov  ecx, [eax-elSizeOffset]
  push eax
  and  ecx, 0FFFFFh
  push ecx
  jmp  short labWBNext

labWBEnd:
  push ebp                      // save the stack restore-point

  // ; init registers
  mov  ebx, [data : %CORE_GC_TABLE + gc_yg_start]
  mov  edx, [data : %CORE_GC_TABLE + gc_yg_end]
  mov  ebp, [data : %CORE_GC_TABLE + gc_shadow]

  // ; collect roots
  lea  eax, [esp+4]
  mov  ecx, [eax]
  mov  esi, [esp+8]
  mov  [data : %CORE_GC_TABLE + gc_yg_current], ebp

labCollectFrame:
  push eax
  call labCollectYG
  pop  eax
  lea  eax, [eax+8]
  mov  esi, [eax+4]
  test esi, esi
  mov  ecx, [eax]
  jnz short labCollectFrame 
  
  // ; save gc_yg_current to mark survived objects
  mov  [data : %CORE_GC_TABLE + gc_yg_current], ebp
  
  // ; switch main YG heap with a shadow one
  mov  eax, [data : %CORE_GC_TABLE + gc_yg_start]
  mov  ebx, [data : %CORE_GC_TABLE + gc_shadow]
  mov  ecx, [data : %CORE_GC_TABLE + gc_yg_end]
  mov  edx, [data : %CORE_GC_TABLE + gc_shadow_end]

  mov  [data : %CORE_GC_TABLE + gc_yg_start], ebx
  mov  [data : %CORE_GC_TABLE + gc_yg_end], edx
  mov  ebx, [esp]
  mov  [data : %CORE_GC_TABLE + gc_shadow], eax  
  mov  ebx, [ebx+4]                           // ; restore object size  
  mov  [data : %CORE_GC_TABLE + gc_shadow_end], ecx

  sub  edx, ebp
  
  pop  ebp
  mov  esp, [ebp-4]  // ; remove wb-roots

  // ; check if it is enough place
  cmp  ebx, edx
  jae  short labFullCollect

  // ; free root set
  mov  esp, ebp

  // ; restore registers
  pop  ebx

  // ; try to allocate once again
  mov  eax, [data : %CORE_GC_TABLE + gc_yg_current]
  mov  ecx, [esp]
  mov  [eax], ebx
  add  ecx, eax
  mov  [data : %CORE_GC_TABLE + gc_yg_current], ecx
  lea  edi, [eax + elObjectOffset]

  // ; GCXT: signal the collecting thread that GC is ended
  // ; should it be placed into critical section?
  xor  ecx, ecx
  mov  esi, [data : %CORE_GC_TABLE + gc_signal]
  // ; clear thread signal var
  mov  [data : %CORE_GC_TABLE + gc_signal], ecx
  push esi
  call extern 'dlls'kernel32.SetEvent 

  mov  eax, edi
  pop  ecx
  pop  ebp
  pop  edi  

  ret

labFullCollect:
  // ; ====== Major Collection ====
  // ; save the stack restore-point
  push ebp                     
	
  // ; expand MG if required
  mov  ecx, [data : %CORE_GC_TABLE + gc_end]
  sub  ecx, [data : %CORE_GC_TABLE + gc_mg_current]
  mov  edx, [data : %CORE_GC_TABLE + gc_yg_current]
  sub  edx, [data : %CORE_GC_TABLE + gc_yg_start]
  cmp  ecx, edx
  ja   labSkipExpand

  mov  eax, [data : %CORE_GC_TABLE + gc_end]
  mov  ecx, 2A000h
  call code : % EXPAND_HEAP

  mov  eax, [data : %CORE_GC_TABLE + gc_header]
  mov  ecx, [data : %CORE_GC_TABLE + gc_end]
  sub  ecx, [data : %CORE_GC_TABLE + gc_start]
  shr  ecx, page_size_order_minus2
  add  eax, ecx
  mov  ecx, 0A800h
  call code : % EXPAND_HEAP

  mov  ecx, [data : %CORE_GC_TABLE + gc_end]
  add  ecx, 15000h
  mov  [data : %CORE_GC_TABLE + gc_end], ecx

labSkipExpand:

  // ; mark both yg and mg objects
  mov  ebx, [data : %CORE_GC_TABLE + gc_yg_start]
  mov  edx, [data : %CORE_GC_TABLE + gc_mg_current]

  // ; collect roots
  lea  eax, [esp+4]
  mov  ecx, [eax]
  mov  esi, [esp+8]

labMGCollectFrame:
  push eax
  call labCollectMG
  pop  eax
  lea  eax, [eax+8]
  mov  esi, [eax+4]
  test esi, esi
  mov  ecx, [eax]
  jnz short labMGCollectFrame 

  // ; compact mg
  mov  esi, [data : %CORE_GC_TABLE + gc_mg_start]
  mov  edi, esi
  sub  edi, [data : %CORE_GC_TABLE + gc_start]
  shr  edi, page_size_order_minus2
  add  edi, [data : %CORE_GC_TABLE + gc_header]

  // ; skip the permanent part
labMGSkipNext:
  mov  ecx, [esi]
  test ecx, ecx
  jns  short labMGSkipEnd
  add  ecx, page_ceil
  mov  eax, esi
  and  ecx, page_align_mask
  lea  eax, [eax + elObjectOffset]
  add  esi, ecx
  mov  [edi], eax
  shr  ecx, page_size_order_minus2
  add  edi, ecx
  cmp  esi, edx
  jb   short labMGSkipNext
  // ; !! undefined behaviour
  xor  ecx, ecx

labMGSkipEnd:
  mov  ebp, esi
  
  // ; compact
labMGCompactNext:
  add  ecx, page_ceil
  and  ecx, page_align_mask  
  add  esi, ecx  
  
  shr  ecx, page_size_order_minus2
  add  edi, ecx
  cmp  esi, edx
  jae  short labMGCompactEnd

labMGCompactNext2:
  mov  ecx, [esi]
  test ecx, ecx
  jns  short labMGCompactNext
  add  ecx, page_ceil
  mov  eax, ebp
  and  ecx, page_align_mask
  lea  eax, [eax + elObjectOffset]
  mov  [edi], eax
  mov  eax, ecx
  shr  eax, page_size_order_minus2
  add  edi, eax

labMGCopy:
  mov  eax, [esi]
  mov  [ebp], eax
  sub  ecx, 4
  lea  esi, [esi+4]
  lea  ebp, [ebp+4]
  jnz  short labMGCopy
  cmp  esi, edx
  jb   short labMGCompactNext2
labMGCompactEnd:

  // ; promote yg
  mov  ebx, [data : %CORE_GC_TABLE + gc_end]
  mov  esi, [data : %CORE_GC_TABLE + gc_yg_start]
  sub  ebx, ebp
  mov  edi, esi
  sub  edi, [data : %CORE_GC_TABLE + gc_start]
  shr  edi, page_size_order_minus2
  mov  edx, [data : %CORE_GC_TABLE + gc_yg_current]
  add  edi, [data : %CORE_GC_TABLE + gc_header]
  jmp  short labYGPromNext2

labYGPromNext:
  add  ecx, page_ceil
  and  ecx, page_align_mask
  add  esi, ecx
  shr  ecx, page_size_order_minus2
  add  edi, ecx
  cmp  esi, edx
  jae  short labYGPromEnd
labYGPromNext2:
  mov  ecx, [esi]
  test ecx, ecx
  jns  short labYGPromNext
  add  ecx, page_ceil
  mov  eax, ebp
  and  ecx, page_align_mask
  // ; raise an exception if it is not enough memory to promote object
  lea  eax, [eax + elObjectOffset]
  sub  ebx, ecx
  js   short labError
  mov  [edi], eax
  mov  eax, ecx
  shr  eax, page_size_order_minus2
  add  edi, eax
labYGProm:
  mov  eax, [esi]
  sub  ecx, 4
  mov  [ebp], eax
  lea  esi, [esi+4]
  lea  ebp, [ebp+4]
  jnz  short labYGProm
  cmp  esi, edx
  jb   short labYGPromNext2
labYGPromEnd:

  // ; get previous heap end
  mov  edx, [data : %CORE_GC_TABLE + gc_mg_current]

  // ; set mg_current, clear yg and survive
  mov  [data : %CORE_GC_TABLE + gc_mg_current], ebp
  mov  eax, [data : %CORE_GC_TABLE + gc_yg_start]
  mov  [data : %CORE_GC_TABLE + gc_yg_current], eax
  
  // ; fix roots
  lea  eax, [esp+4]
  mov  ecx, [eax]
  mov  esi, [esp+8]

  mov  ebx, [data : %CORE_GC_TABLE + gc_yg_start]
  mov  ebp, [data : %CORE_GC_TABLE + gc_start]

labFixRoot:
  push eax
  call labFixObject
  pop  eax
  lea  eax, [eax+8]
  mov  esi, [eax+4]
  test esi, esi
  mov  ecx, [eax]
  jnz  short labFixRoot 

  // ; clear WBar
  mov  ecx, [data : %CORE_GC_TABLE + gc_end ] 
  mov  edi, [data : %CORE_GC_TABLE + gc_mg_wbar]
  sub  ecx, [data : %CORE_GC_TABLE + gc_mg_start]
  xor  eax, eax
  shr  ecx, page_size_order // !! pay attention
  rep  stos 
	
  // ; free root set
  mov  esp, [esp]
  pop  ebx

  // ; allocate
  mov  eax, [data : %CORE_GC_TABLE + gc_yg_current]
  mov  ecx, [esp]
  mov  edx, [data : %CORE_GC_TABLE + gc_yg_end]
  add  ecx, eax
  cmp  ecx, edx
  jae  labBigAlloc
  mov  [eax], ebx
  mov  [data : %CORE_GC_TABLE + gc_yg_current], ecx
  lea  edi, [eax + elObjectOffset]

  // ; GCXT: signal the collecting thread that GC is ended
  // ; should it be placed into critical section?
  xor  ecx, ecx
  mov  esi, [data : %CORE_GC_TABLE + gc_signal]
  // ; clear thread signal var
  mov  [data : %CORE_GC_TABLE + gc_signal], ecx
  push esi
  call extern 'dlls'kernel32.SetEvent 

  mov  eax, edi
  pop  ecx
  pop  ebp
  pop  edi  
  ret

labError:
  // ; restore stack
  mov  esp, [esp]
  pop  ebx
  pop  ecx
  pop  ebp
  pop  edi 

labError2:
  mov  ebx, 0C0000017h
  call code : % BREAK
  ret  

// ; bad luck, we have to expand GC
labBigAlloc2:
  push ecx
  push ebx

  mov  eax, [data : %CORE_GC_TABLE + gc_end]
  mov  ecx, 2A000h
  call code : % EXPAND_HEAP

  mov  eax, [data : %CORE_GC_TABLE + gc_header]
  mov  ecx, [data : %CORE_GC_TABLE + gc_end]
  sub  ecx, [data : %CORE_GC_TABLE + gc_start]
  shr  ecx, page_size_order_minus2
  add  eax, ecx
  mov  ecx, 0A800h
  call code : % EXPAND_HEAP

  mov  ecx, [data : %CORE_GC_TABLE + gc_end]
  add  ecx, 15000h
  mov  [data : %CORE_GC_TABLE + gc_end], ecx

  pop  ebx
  pop  ecx

labBigAlloc:
  // ; try to allocate in the mg
  sub  ecx, eax
  cmp  ecx, 800000h
  jae  labError2

  mov  eax, [data : %CORE_GC_TABLE + gc_mg_current]
  mov  edx, [data : %CORE_GC_TABLE + gc_end]
  add  ecx, eax
  cmp  ecx, edx
  jae  labBigAlloc2
  mov  [eax], ebx
  mov  [data : %CORE_GC_TABLE + gc_mg_current], ecx
  lea  eax, [eax + elObjectOffset]

  // ; mark it as root in WB
  cmp  ebx, 0800000h
  jae  short labSkipBigAlloc

  mov  ecx, eax
  mov  esi, [data : %CORE_GC_TABLE + gc_header]
  sub  ecx, [data : %CORE_GC_TABLE + gc_start]
  shr  ecx, page_size_order
  mov  byte ptr [ecx + esi], 1  

labSkipBigAlloc:
  mov  edi, eax
  // ; GCXT: signal the collecting thread that GC is ended
  // ; should it be placed into critical section?
  xor  ecx, ecx
  mov  esi, [data : %CORE_GC_TABLE + gc_signal]
  // ; clear thread signal var
  mov  [data : %CORE_GC_TABLE + gc_signal], ecx
  push esi
  call extern 'dlls'kernel32.SetEvent 

  mov  eax, edi
  pop  ecx
  pop  ebp
  pop  edi  
  ret  

  // ; start collecting: esi => ebp, [ebx, edx] ; ecx - count
labCollectYG:
  push 0

  lea  ecx, [ecx+4]
  lea  esi, [esi-4]

labYGNext:
  lea  esi, [esi+4]
  sub  ecx, 4
  jz   labYGResume

labYGCheck:
  mov  eax, [esi]

  // ; check if it valid reference
  cmp  eax, ebx
  jl   short labYGNext  
  nop
  cmp  edx, eax
  jl   short labYGNext

  // ; check if it was collected
  mov  edi, [eax-elSizeOffset]
  test edi, edi
  js   labYGContinue

  // ; save previous ecx field
  push ecx

  // ; copy object size
  mov  [ebp], edi
  
  // ; copy object vmt
  mov  ecx, [eax - elVMTOffset]
  mov  [ebp + 04h], ecx
  
  // ; mark as collected
  or   [eax - elSizeOffset], 80000000h

  // ; reserve shadow YG
  mov  ecx, edi
  add  ecx, page_ceil
  lea  edi, [ebp + elObjectOffset]
  and  ecx, page_align_mask  
  mov  [esi], edi          // ; update reference 
  add  ebp, ecx

  // ; get object size
  mov  ecx, [eax-elSizeOffset]
  and  ecx, 8FFFFFh

  // ; save ESI
  push esi
  mov  esi, eax

  // ; save new reference
  mov  [eax - elVMTOffset], edi

  // ; check if the object has fields
  cmp  ecx, 800000h

  // ; save original reference
  push eax

  // ; collect object fields if it has them
  jb   labYGCheck

  lea  esp, [esp+4]
  jz   short labYGSkipCopyData

  // ; copy meta data object to shadow YG
  add  ecx, 3
  and  ecx, 0FFFFCh

labYGCopyData:
  mov  eax, [esi]
  sub  ecx, 4
  mov  [edi], eax
  lea  esi, [esi+4]
  lea  edi, [edi+4]
  jnz  short labYGCopyData

labYGSkipCopyData:
  pop  esi
  pop  ecx
  jmp  labYGNext

labYGResume:
  // ; copy object to shadow YG
  pop  edi
  test edi, edi
  jz   short labYGEnd

  mov  ecx, [edi-elSizeOffset]
  mov  esi, [edi - elVMTOffset]
  and  ecx, 0FFFFFh

labYGCopy:
  mov  eax, [edi]
  sub  ecx, 4
  mov  [esi], eax
  lea  esi, [esi+4]
  lea  edi, [edi+4]
  jnz  short labYGCopy

  pop  esi
  pop  ecx
  jmp  labYGNext

  nop
labYGEnd:
  ret

labYGContinue:
  // ; update reference
  mov  edi, [eax - elVMTOffset]
  mov  [esi], edi
  jmp  labYGNext

  // ---- start collecting: esi => ebp, [ebx, edx] ; ecx - count ---
labCollectMG:

  lea  ecx, [ecx+4]
  push 0
  lea  esi, [esi-4]
  push 0

labMGNext:
  sub  ecx, 4
  lea  esi, [esi+4]
  jz   short labMGResume

labMGCheck:
  mov  eax, [esi]

  // ; check if it valid reference
  cmp  eax, ebx
  jl   short labMGNext  
  nop
  cmp  edx, eax
  jl   short labMGNext

  // ; check if it was collected
  mov  edi, [eax-elSizeOffset]
  test edi, edi
  js   short labMGNext

  // ; mark as collected
  or  [eax - elSizeOffset], 080000000h

  cmp  edi, 0800000h
  jae  short labMGNext

  // ; save previous ecx field
  push ecx

  // ; get object size
  mov  ecx, [eax - elSizeOffset]

  // ; save ESI
  push esi
  and  ecx, 0FFFFFh

  mov  esi, eax

  // ; collect object fields if it has them
  jmp   short labMGCheck

labMGResume:
  pop  esi
  pop  ecx
  test esi, esi
  jnz  short labMGNext

  nop
labMGEnd:
  ret

labFixObject:

  lea  ecx, [ecx+4]
  push 0
  lea  esi, [esi-4]
  push 0

labFixNext:
  sub  ecx, 4
  lea  esi, [esi+4]
  jz   short labFixResume

labFixCheck:
  mov  eax, [esi]

  // ; check if it valid reference
  cmp  eax, ebx
  jl   short labFixNext
  nop
  cmp  edx, eax
  jl   short labFixNext

  lea  edi, [eax-elObjectOffset]

  sub  edi, ebp
  shr  edi, page_size_order_minus2
  add  edi, [data : %CORE_GC_TABLE + gc_header]

  mov  eax, [edi]
  mov  [esi], eax

  // ; make sure the object was not already fixed
  mov  edi, [eax - elSizeOffset]
  test edi, edi
  jns  short labFixNext

  and  edi, 7FFFFFFFh
  mov  [eax - elSizeOffset], edi

  cmp  edi, 0800000h
  jae  short labFixNext

  // ; save previous ecx field
  push ecx

  // ; get object size
  mov  ecx, [eax - elSizeOffset]
  and  ecx, 0FFFFFh

  // ; save ESI
  push esi
  mov  esi, eax

  // ; collect object fields if it has them
  jmp   short labFixCheck

labFixResume:
  pop  esi
  pop  ecx
  test esi, esi
  jnz  short labFixNext
  nop

  ret

end

// --- System Core Functions --

procedure % INIT
  // ; initialize fpu
  finit

  // GCXT: initialize signal
  xor  ebx, ebx
  mov  [data : %CORE_GC_TABLE + gc_signal], ebx

  // ; initialize
  mov  ecx, [data : %CORE_STAT_COUNT]
  mov  edi, data : %CORE_STATICROOT
  shr  ecx, 2
  xor  eax, eax
  rep  stos

labNext:
  mov  ecx, 10000000h
  mov  ebx, [data : %CORE_GC_SIZE]
  and  ebx, 0FFFFFF80h     // ; align to 128
  shr  ebx, page_size_order_minus2
  call code : %NEW_HEAP
  mov  [data : %CORE_GC_TABLE + gc_header], eax

  mov  ecx, 40000000h
  mov  ebx, [data : %CORE_GC_SIZE]
  and  ebx, 0FFFFFF80h     // align to 128
  call code : %NEW_HEAP
  mov  [data : %CORE_GC_TABLE + gc_start], eax

  // ; initialize yg
  mov  [data : %CORE_GC_TABLE + gc_start], eax
  mov  [data : %CORE_GC_TABLE + gc_yg_start], eax
  mov  [data : %CORE_GC_TABLE + gc_yg_current], eax

  // ; initialize gc end
  mov  ecx, [data : %CORE_GC_SIZE]
  and  ecx, 0FFFFFF80h     // ; align to 128
  add  ecx, eax
  mov  [data : %CORE_GC_TABLE + gc_end], ecx

  // ; initialize gc shadow
  mov  ecx, [data : %CORE_GC_SIZE + gcs_YGSize]
  and  ecx, page_mask
  add  eax, ecx
  mov  [data : %CORE_GC_TABLE + gc_yg_end], eax
  mov  [data : %CORE_GC_TABLE + gc_shadow], eax

  // ; initialize gc mg
  add  eax, ecx
  mov  [data : %CORE_GC_TABLE + gc_shadow_end], eax
  mov  [data : %CORE_GC_TABLE + gc_mg_start], eax
  mov  [data : %CORE_GC_TABLE + gc_mg_current], eax
  
  // ; initialize wbar start
  mov  edx, eax
  sub  edx, [data : %CORE_GC_TABLE + gc_start]
  shr  edx, page_size_order
  add  edx, [data : %CORE_GC_TABLE + gc_header]
  mov  [data : %CORE_GC_TABLE + gc_mg_wbar], edx
  
  // ; GCXT: assign tls entry
  mov  ebx, [data : %CORE_TLS_INDEX]
  mov  ecx, fs:[2Ch]
  mov  esi, [ecx + ebx*4]

  // ; init thread flags  
  mov  [esi + tls_flags], 0       

  call code : %NEW_EVENT
  mov  [esi + tls_sync_event], eax     

  mov  eax, data : %THREAD_TABLE
  mov  [eax], esi       // ; save tls reference 

  mov  ecx, [data : %CORE_GC_SIZE + gcs_TTSize]
  mov  [eax-4], ecx
  
  ret

end

procedure % NEWFRAME

  // ; put frame end and move procedure returning address
  pop  edx           

  // ; set SEH handler
  mov  ebx, code : "$native'coreapi'seh_handler"
  push ebx
  mov  ecx, fs:[0]
  push ecx
  mov  fs:[0], esp

  // ; GCXT                                                               
  // ; get thread table entry from tls
  mov  ecx, [data : %CORE_TLS_INDEX]
  mov  esi, fs:[2Ch]
  mov  esi, [esi+ecx*4]

  xor  ebx, ebx

  push ebp
  push ebx
  push ebx

  // ; GCXT
  // ; set stack frame pointer / bottom stack pointer
  mov  ebp, esp 
  mov  [esi + tls_stack_bottom], esp
  push edx
  mov  [esi + tls_stack_frame], ebx
  
  // ; GCXT
  // ; set thread table length
  mov  ebx, 1
  mov  [data : %CORE_GC_TABLE + tt_ptr], ebx   

  mov  ebx, code : "$native'coreapi'default_handler"

  // ; init default critical handler
  mov  [data : % CORE_ET_TABLE], ebx

  call code : % INIT_ET  

  ret

end

procedure % ENDFRAME

  // ; save return pointer
  pop  ecx  
  
  xor  edx, edx
  lea  esp, [esp+8]
  pop  ebp

  // ; restore return pointer
  push ecx   
  ret

end

// ; init exception table, ebx contains default handler address
procedure % INIT_ET

  pop esi

  mov edx, ebx

  // ; GCXT: get current thread frame
  mov  ebx, [data : %CORE_TLS_INDEX]
  mov  ecx, fs:[2Ch]
  mov  ebx, [ecx+ebx*4]

  // ; set default exception handler
  mov  [ebx + tls_catch_addr], edx
  mov  [ebx + tls_catch_level], esp
  mov  [ebx + tls_catch_frame], ebp

  push esi

  ret

end 

procedure % RESTORE_ET

  // ; GCXT: get current thread frame
  mov  ebx, [data : %CORE_TLS_INDEX]
  mov  ecx, fs:[2Ch]
  mov  ebx, [ecx+ebx*4]

  pop  edx
  mov  esp, [ebx + tls_catch_level]
  push edx

  ret

end 

// ; NOTE : some functions (e.g. system'core_routines'win_WndProc) assumes the function reserves 12 bytes
// ; does not affect eax
procedure % OPENFRAME

  // ; GCXT: get thread table entry from tls
  mov  ebx, [data : %CORE_TLS_INDEX]
  mov  esi, fs:[2Ch]
  xor  edi, edi
  mov  esi, [esi+ebx*4]
                                        
  // ; save return pointer
  pop  ecx  

  // ; GCXT: get thread table entry from tls
  // ; save previous pointer / size field
  mov  esi, [esi + tls_stack_frame]
  push ebp
  push esi                                
  push edi                              
  mov  ebp, esp
  
  // ; restore return pointer
  push ecx   
  ret

end

// ; does not affect eax
procedure % CLOSEFRAME

  // ; GCXT: get thread table entry from tls
  mov  ebx, [data : %CORE_TLS_INDEX]
  mov  esi, fs:[2Ch]
  xor  edi, edi
  mov  esi, [esi+ebx*4]
                                        
  // ; save return pointer
  pop  ecx  

  // ; GCXT
  lea  esp, [esp+4]
  pop  edx
  mov  [esi + tls_stack_frame], edx
  pop  ebp
  
  // ; restore return pointer
  push ecx   
  ret

end

procedure % NEWTHREAD

  push eax
  
  // ; GCXT
  mov  edx, data : %THREAD_TABLE
  mov  esi, data : %CORE_GC_TABLE + tt_lock
  mov  ecx, [edx - 4]

labWait:
  // ; set lock
  xor  eax, eax
  mov  edx, 1
  lock cmpxchg dword ptr[esi], edx
  jnz  short labWait

  mov  ebx, [data : %CORE_GC_TABLE + tt_ptr]
  sub  ecx, ebx
  jz   short labSkipSave

  add  ebx, 1
  mov  [data : %CORE_GC_TABLE + tt_ptr], ebx

labSkipSave:

  // ; free lock
  // ; could we use mov [esi], 0 instead?
  mov  edx, -1
  lock xadd [esi], edx

  xor  eax, eax

  // check if there is a place in thread table
  test ecx, ecx
  jz   short lErr
  
  sub  ebx, 1
  mov  esi, data : %THREAD_TABLE
  lea  esi, [esi+ebx*4]

  // ; assign tls entry
  mov  ebx, [data : %CORE_TLS_INDEX]
  push 0

  mov  eax, fs:[2Ch]
  push 0

  mov  eax, [eax + ebx*4] 
  push 0FFFFFFFFh //-1

  mov  [esi], eax               // ; save tls entry
  push 0
  mov  esi, eax

  call extern 'dlls'kernel32.CreateEventW

  // ; initialize thread entry
  mov  [esi + tls_sync_event], eax     // ; set thread event handle

  mov  [esi+tls_flags], 0              // ; init thread flags  

  pop  eax
  pop  edx                             // ; put frame end and move procedure returning address

  xor  ebx, ebx
  push ebp
  push ebx                      
  push ebx

  // ; set stack frame pointer  
  mov  ebp, esp 
  mov  [esi + tls_stack_frame], ebx
  mov  [esi + tls_stack_bottom], esp

  // ; restore return pointer
  push edx              

  mov  ebx, code : "$native'coreapi'core_thread_handler"
  call code : % INIT_ET

  ret

lErr:
  add esp, 4 
  ret

end

procedure % CLOSETHREAD

  // ; GCXT
  mov  ebx, [data : %CORE_TLS_INDEX]
  mov  edi, fs:[2Ch]

  mov  esi, data : %CORE_GC_TABLE + tt_lock

labWait:
  // ; set lock
  xor  eax, eax  
  mov  edx, 1
  lock cmpxchg dword ptr[esi], edx
  jnz  short labWait

  // ; tls reference
  mov  eax, [edi + ebx*4]           
  mov  ecx, [data : %CORE_GC_TABLE + tt_ptr]
  mov  edi, data : %THREAD_TABLE

  // ; find the current thread entry
labSearch:
  test ecx, ecx
  jz   short labNotFound

  cmp  [edi], eax
  lea  edi, [edi+4]
  lea  ecx, [ecx-1]
  jnz   short labSearch

  // ; delete the entry
  test ecx, ecx
  jz   short labSkipDelete

labDelete:
  mov  ebx, [edi]
  mov  [edi-4], ebx
  lea  edi, [edi+4]
  sub  ecx, 1
  jnz   short labDelete
  
labSkipDelete:
  mov  ecx, [data : %CORE_GC_TABLE + tt_ptr]
  mov  edi, eax
  sub  ecx, 1
  mov  ebx, [edi + tls_sync_event]
  mov  [data : %CORE_GC_TABLE + tt_ptr], ecx

  // ; close handle

  push ebx
  call extern 'dlls'kernel32.CloseHandle

labNotFound:

  // ; free lock
  // ; could we use mov [esi], 0 instead?
  mov  edx, -1
  lock xadd [esi], edx

  pop  edx
  lea  esp, [esp+0Ch]
  push edx

lErr:
  ret
  
end

// --- THREAD_WAIT ---
// GCXT: it is presumed that gc lock is on, edx - contains the collecting thread event handle

procedure % THREAD_WAIT

  push eax
  push edi
  push ebp
  mov  edi, esp

  push 0FFFFFFFFh // -1     // WaitForSingleObject::dwMilliseconds
  push edx                  // hHandle

  // ; set lock
  mov  ebx, data : %CORE_GC_TABLE + gc_lock
labWait:
  mov edx, 1
  xor eax, eax  
  lock cmpxchg dword ptr[ebx], edx
  jnz  short labWait

  // ; find the current thread entry
  mov  edx, fs:[2Ch]
  mov  eax, [data : %CORE_TLS_INDEX]  
  mov  eax, [edx+eax*4]

  mov  esi, [eax+tls_sync_event]   // ; get current thread event
  mov  [eax+tls_stack_frame], edi                  // ; lock stack frame

  // ; signal the collecting thread that it is stopped
  push esi
  mov  edi, data : %CORE_GC_TABLE + gc_lock

  // ; signal the collecting thread that it is stopped
  call extern 'dlls'kernel32.SetEvent

  // ; free lock
  // ; could we use mov [esi], 0 instead?
  mov  ebx, 0FFFFFFFFh
  lock xadd [edi], ebx

  // ; stop until GC is ended
  call extern 'dlls'kernel32.WaitForSingleObject

  add  esp, 4
  pop  edi
  pop  eax

  ret

end

// ; ==== Command Set ==

// ; snop
inline % 4

  // ; safe point
  mov  edx, [data : %CORE_GC_TABLE + gc_signal]
  test edx, edx                       // ; if it is a collecting thread, waits
  jz   short labConinue               // ; otherwise goes on

  nop
  nop
  call code : %THREAD_WAIT            // ; waits until the GC is stopped

labConinue:

end

// ; throw
inline % 7

  // ; GCXT: get current thread frame
  mov  esi, [data : %CORE_TLS_INDEX]
  mov  edx, fs:[2Ch]
  mov  esi, [edx+esi*4]
  jmp  [esi + tls_catch_addr]

end

// ; unhook
inline % 1Dh

  // ; GCXT: get current thread frame
  mov  edx, [data : %CORE_TLS_INDEX]
  mov  esi, fs:[2Ch]
  mov  edx, [esi+edx*4]

  mov  esp, [edx + tls_catch_level]  
  mov  ebp, [edx + tls_catch_frame]
  mov  esi, [esp]
  mov  [edx + tls_catch_level], esi
  mov  esi, [esp+4]
  mov  [edx + tls_catch_frame], esi
  mov  esi, [esp+8]
  mov  [edx + tls_catch_addr], esi
  add  esp, 12
  
end

// ; include
inline % 25h
       
  add  esp, 4
  mov  edx, fs:[2Ch]
  mov  eax, [data : %CORE_TLS_INDEX]
  mov  esi, [edx+eax*4]
  mov  [esi + tls_flags], 0

end

// ; exclude
inline % 26h
                                                       
  mov  edx, fs:[2Ch]
  mov  eax, [data : %CORE_TLS_INDEX]
  mov  esi, [edx+eax*4]
  mov  [esi + tls_flags], 1
  push ebp     
  mov  [esi + tls_stack_frame], esp

end

// ; trylock
inline % 27h

  // ; GCXT: try to lock
  mov esi, [esp]
  xor eax, eax
  mov ebx, 1
  lock cmpxchg byte ptr[esi - elSyncOffset], bl
  mov  ebx, eax
  mov  eax, esi

end

// ; freelock
inline % 28h

  mov  edx, -1

  // ; free lock
  lock xadd byte ptr [eax - elSyncOffset], dl

end

// ; rethrow
inline % 29h

  // ; GCXT: get current thread frame
  mov  esi, [data : %CORE_TLS_INDEX]
  mov  edx, fs:[2Ch]
  mov  edx, [edx+esi*4]

  mov  esi, [edx + tls_catch_level]  
  mov  ebx, [esi]
  mov  [edx + tls_catch_level], ebx
  mov  ebx, [esi+4]
  mov  [edx + tls_catch_frame], ebx
  mov  ebx, [esi+8]
  mov  [edx + tls_catch_addr], ebx

  jmp  [edx + tls_catch_addr]

end

// ; hook label (ecx - offset)
// ; NOTE : hook calling should be the first opcode

inline % 0A6h

  call code : %HOOK

  // ; GCXT: get current thread frame
  mov  ebx, [data : %CORE_TLS_INDEX]
  mov  edx, fs:[2Ch]
  mov  ebx, [edx+ebx*4]

  push [ebx + tls_catch_addr]
  push [ebx + tls_catch_frame]
  push [ebx + tls_catch_level]  
  mov  [ebx + tls_catch_addr], ecx
  mov  [ebx + tls_catch_level], esp
  mov  [ebx + tls_catch_frame], ebp
  
end
