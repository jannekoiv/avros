#include <avr/io.h>
#include "avros_asm.h"
        ;; temp storage registers
#define tmp r18
#define tmp2 r19
#define tmp3 r20
#define tmp4 r21
        ;; system call argument registers
#define arg1 r24
#define arg2 r25
#define arg3 r22
#define arg4 r23
        ;; system call return value registers
#define ret1 r24
#define ret2 r25
#define ret3 r22
#define ret4 r23
        ;; data type sizes
#define BYTE 1
#define WORD 2
        ;; task structure byte offsets
#define TASK_ID 0
#define TASK_STATE (TASK_ID + BYTE)
#define TASK_LOCK (TASK_STATE + BYTE)
#define TASK_TIMER (TASK_LOCK + BYTE)
#define TASK_STACK_PTR (TASK_TIMER + WORD)
#define TASK_STACK (TASK_STACK_PTR + WORD)
#define TASK_SIZE (TASK_STACK + STACK_SIZE)
#define TASK_STACK_BOTTOM (TASK_SIZE - 1)
#define TASK_CONTEXT_SIZE 35
#define TASK_ADDR_IDLE (tasks + TASK_SIZE * TASK_CNT)
        ;; identifiers for lock types
#define LOCK_SEM 0b01000000
#define LOCK_MTX 0b10000000
        ;; value to add to timer counter when preparing next scheduler call
#define TCNT_ADD CPU_FREQ / (SCHED_FREQ * 256)
        
	.data                                   ; data segment begins
tasks:  .skip TASK_SIZE * (TASK_CNT + 1)        ; task array, one extra slot for idle task
task_addr: .skip WORD                           ; address of current task
atomic_intr: .skip BYTE                         ; atomic block interruption flag
sys_time: .skip BYTE * 4                        ; four bytes system time
semaphores: .skip BYTE * SEM_CNT                ; semaphore array
mutexes: .skip BYTE * MTX_CNT                   ; mutex array
        
        .text                                   ; code segment begins
        ;; store immediate byte to i/o at direct address
        .macro outi addr, val, tmp
        ldi \tmp, \val
        out \addr, \tmp
        .endm

        ;; store immediate byte to data space at indirect address
        .macro sti addr, val, tmp
        ldi \tmp, \val
        st \addr, \tmp
        .endm
        
        ;; store immediate byte to data space at direct address
        .macro stsi addr, val, tmp
        ldi \tmp, \val
        sts \addr, \tmp
        .endm

        ;; store immediate byte to data space at indirect address with displacement
        .macro stdi addr, val, tmp
        ldi \tmp, \val
        std \addr, \tmp
        .endm

        ;; load immediate word to register pair
        .macro ldiw regl, regh, val
        ldi \regl, lo8(\val)
        ldi \regh, hi8(\val)
        .endm

        ;; add immediate word to register pair
        .macro addiw regl, regh, val
        subi \regl, lo8(-(\val))
        sbci \regh, hi8(-(\val))
        .endm
        
        ;; enable output compare interrupt for timer 0
        .macro oci_enable
        in tmp, _SFR_IO_ADDR(TIMSK)             ; load current flags
        sbr tmp, 1 << OCIE0                     ; add OCIE0 flag
        out _SFR_IO_ADDR(TIMSK), tmp            ; store new flags
        .endm

        ;; disable output compare interrupt for timer 0
        .macro oci_disable
        in tmp, _SFR_IO_ADDR(TIMSK)             ; load current flags
        cbr tmp, 1 << OCIE0                     ; remove OCIE0 flag
        out _SFR_IO_ADDR(TIMSK), tmp            ; store new flags
        .endm

        ;; begin atomic block, store global interrupt flag
        .macro ATOMIC_BEGIN
        brid 1001f                              ; step over if interrupts disabled
        stsi atomic_intr, 1, tmp
        rjmp 1002f
1001:
        stsi atomic_intr, 0, tmp
1002:
        cli
        .endm

        ;; end atomic block, restore global interrupt flag to previous state, return
        .macro ATOMIC_END
        lds tmp, atomic_intr
        cpi tmp, 0
        breq 1101f
        reti                                    ; enable interrupts and return
1101:
        ret                                     ; return
        .endm
        
        ;; initialize array of size at address to value
        .macro memset addr, val, size, cnt, tmp
        ldi \cnt, 0                             ; set counter
        ldiw ZL, ZH, \addr                      ; store array address to Z
        rjmp 1202f                              ; jump to counter comparison
1201:
        sti Z+, \val, \tmp                      ; store value to array
        inc \cnt                                ; increase counter
1202:
        cpi \cnt, \size                         ; compare counter
        brlo 1201b                              ; next iteration
        .endm
        
        ;; save task execution context
        .macro save
        push r0                                 ; push r0
        in r0, _SFR_IO_ADDR(SREG)               ; load status register
        cli                                     ; disable interrupts
        push r0                                 ; push status register
        push r1
        push r2
        push r3
        push r4
        push r5
        push r6
        push r7
        push r8
        push r9
        push r10
        push r11
        push r12
        push r13
        push r14
        push r15
        push r16
        push r17
        push r18
        push r19
        push r20
        push r21
        push r22
        push r23
        push r24
        push r25
        push r26
        push r27
        push r28
        push r29
        push r30
        push r31
        .endm

        ;; restore task execution context
        .macro restore
        pop r31
        pop r30
        pop r29
        pop r28
        pop r27
        pop r26
        pop r25
        pop r24
        pop r23
        pop r22
        pop r21
        pop r20
        pop r19
        pop r18
        pop r17
        pop r16
        pop r15
        pop r14
        pop r13
        pop r12
        pop r11
        pop r10
        pop r9
        pop r8
        pop r7
        pop r6
        pop r5
        pop r4
        pop r3
        pop r2
        pop r1
        pop r0                                  ; pop status register
        out _SFR_IO_ADDR(SREG), r0              ; store status register
        pop r0                                  ; pop r0
        .endm

        
        ;; initialize operating system
        .global init
init:
        ;; initialize tasks, all tasks killed by default
        clr tmp                                 ; init task counter
        ldiw ZL, ZH, tasks                      ; load address of task array to Z
        rjmp init_2                             ; counter comparison
init_1:
        inc tmp                                 ; increase task counter
        std Z + TASK_ID, tmp                    ; store id
        stdi Z + TASK_STATE, TASK_KILLED, tmp2  ; store state
        stdi Z + TASK_LOCK, 0, tmp2             ; store lock number
        stdi Z + TASK_TIMER, 0, tmp2            ; store timer lo byte
        stdi Z + TASK_TIMER + 1, 0, tmp2        ; store timer hi byte
        stdi Z + TASK_STACK_PTR, 0, tmp2        ; store stack pointer lo byte
        stdi Z + TASK_STACK_PTR + 1, 0, tmp2    ; store stack pointer hi byte
        addiw ZL, ZH, TASK_SIZE                 ; add offset to next task
init_2:
        cpi tmp, TASK_CNT + 1                   ; compare task counter
        brne init_1                             ; next iteration
        ;; initialize semaphores
        memset semaphores, 1, (BYTE * SEM_CNT), tmp, tmp2 
        ;; initialize mutexes
        memset mutexes, 0, (BYTE * MTX_CNT), tmp, tmp2 
        stsi atomic_intr, 0, tmp                ; clear atomic block interruption flag 
        memset sys_time, 0, (BYTE * 4), tmp, tmp2 ; clear system time
        ;; create idle task
        rcall create_idle
        ;; store address of last task to task pointer,
        ;; first task slot will be used when creating main task
        stsi task_addr, lo8(tasks + TASK_SIZE * (TASK_CNT - 1)), tmp 
        stsi task_addr + 1, hi8(tasks + TASK_SIZE * (TASK_CNT - 1)), tmp
        rcall create                            ; create main task
        ldd tmp, Z + TASK_STACK_PTR             ; load lower byte of task stack pointer
        ldd tmp2, Z + TASK_STACK_PTR + 1        ; load upper byte of task stack pointer
        ;; fix stack pointer, main task need no preallocated context space
        addiw tmp, tmp2, (TASK_CONTEXT_SIZE - 2) 
        out _SFR_IO_ADDR(SPL), tmp              ; store lower byte of cpu stack pointer
        out _SFR_IO_ADDR(SPH), tmp2             ; store upper byte of cpu stack pointer
        sts task_addr, ZL                       ; store address of main task to task pointer
        sts task_addr + 1, ZH                   ;
        outi _SFR_IO_ADDR(TCCR0), (1 << CS02), tmp ; set timer 0 speed to xtal / 256
        oci_enable                              ; enable output compare interrupt
        outi _SFR_IO_ADDR(TCNT0), 0, tmp        ; reset timer 0 counter
        outi _SFR_IO_ADDR(OCR0), TCNT_ADD, tmp  ; prepare first scheduler interrupt
        rcall switch                            ; switch to main task
        rjmp schedule                           ; schedule main task

        
        ;; prevent task scheduling
        .global lock
lock:
        ATOMIC_BEGIN                            ; begin atomic block
        oci_disable                             ; disable output compare interrupt
        ATOMIC_END                              ; end atomic block


        ;; allow task scheduling
        .global unlock
unlock:
        ATOMIC_BEGIN                            ; begin atomic block
        oci_enable                              ; enable output compare interrupt
        ATOMIC_END                              ; end atomic block


        ;; find task
find:
        ldi tmp3, TASK_CNT                      ; init task counter
        lds ZL, task_addr                       ; load address of current task to Z
        lds ZH, task_addr + 1                   ;
        rjmp find_3                             ; counter comparison
find_1:
        dec tmp3                                ; decrease task counter
        addiw ZL, ZH, TASK_SIZE                 ; move pointer to next task
        ldi tmp4, hi8(TASK_ADDR_IDLE)           ; bound check task pointer
        cpi ZL, lo8(TASK_ADDR_IDLE)             ;
        cpc ZH, tmp4                            ;
        brlo find_2                             ; step over if in bounds
        ldiw ZL, ZH, tasks                      ; reset task pointer
find_2:
        mov XL, ZL                              ; copy lower byte of task address to XL
        mov XH, ZH                              ; copy upper byte of task address to XH
        add XL, tmp2                            ; add offset to task struct
        clr tmp4                                ; clear tmp4 for adding zero with carry
        adc XH, tmp4                            ; add zero with carry
        ld tmp4, X                              ; load task state
        cp tmp, tmp4                            ; check if matching task
        brne find_3                             ; step over
        ret                                     ; ready task found, return
find_3:
        cpi tmp3, 0                             ; compare task counter
        brne find_1                             ; next iteration
        ldi ZL, lo8(TASK_ADDR_IDLE)             ; task not found
        ldi ZH, hi8(TASK_ADDR_IDLE)             ; set Z to address of idle task
        ret

        
        ;; perform a task switch from current to next task.
switch:
        pop tmp2                                ; store return address
        pop tmp3                                ;
        ;; store current cpu stack pointer to stack pointer of current task
        mov XL, ZL                              ; save Z, contains address of next task
        mov XH, ZH                              ;
        lds ZL, task_addr                       ; load address of current task to Z
        lds ZH, task_addr + 1                   ;
        in tmp, _SFR_IO_ADDR(SPL)               ; load lower byte of cpu stack pointer
        std Z + TASK_STACK_PTR, tmp             ; store lower byte of task stack pointer
        in tmp, _SFR_IO_ADDR(SPH)               ; load upper byte of cpu stack pointer
        std Z + TASK_STACK_PTR + 1, tmp         ; store upper byte of task stack pointer
        mov ZL, XL                              ; restore Z
        mov ZH, XH                              ;
        ;; set new cpu stack pointer
        ldd tmp, Z + TASK_STACK_PTR             ; load lower byte of task stack pointer
        out _SFR_IO_ADDR(SPL), tmp              ; store lower byte of cpu stack pointer
        ldd tmp, Z + TASK_STACK_PTR + 1         ; load upper byte of task stack pointer
        out _SFR_IO_ADDR(SPH), tmp              ; store upper byte of cpu stack pointer
        sts task_addr, ZL                       ; store address of current task
        sts task_addr + 1, ZH                   ;
        push tmp3                               ; restore return address
        push tmp2                               ;
        ret                                     ; return


        ;; process timers
timers:
        clr tmp                                 ; init task counter
        ldiw ZL, ZH, tasks                      ; load address of task array to Z
        rjmp timers_3                           ; counter comparison
timers_1:
        inc tmp                                 ; increase task counter
        ldd XL, Z + TASK_TIMER                  ; load lower byte of timer
        ldd XH, Z + TASK_TIMER + 1              ; load upper byte of timer
        ldi tmp2, 0                             ; check if timer value is zero
        cpi XL, 0                               ; compare lower byte
        cpc XH, tmp2                            ; compare upper byte
        breq timers_2                           ; step over
        sbiw XL, 1                              ; decrease timer value
        brne timers_2                           ; check if timer value decremented to zero
        stdi Z + TASK_STATE, TASK_RUNNING, tmp2 ; wake up task
timers_2:
        std Z + TASK_TIMER, XL                  ; store lower byte of timer
        std Z + TASK_TIMER + 1, XH              ; store upper byte of timer
        addiw ZL, ZH, TASK_SIZE                 ; add offset to next task
timers_3:
        cpi tmp, TASK_CNT                       ; compare task counter
        brne timers_1                           ; next iteration
        ret

        
        ;; increases system time
inc_time:
        ldi tmp2, 1                             ; load 1 to tmp
        lds tmp, sys_time                       ; load first byte
        add tmp, tmp2                           ; increment first byte
        sts sys_time, tmp                       ; store first byte
        clr tmp2                                ; clear tmp
        lds tmp, sys_time + 1                   ; load second byte
        adc tmp, tmp2                           ; increment second byte
        sts sys_time + 1, tmp                   ; store second byte
        lds tmp, sys_time + 2                   ; load third byte
        adc tmp, tmp2                           ; increment third byte
        sts sys_time + 2, tmp                   ; store third byte
        lds tmp, sys_time + 3                   ; load fourth byte
        adc tmp, tmp2                           ; increment fourth byte
        sts sys_time + 3, tmp                   ; store fourth byte
        ret

        
        ;; idle task, running only when there are no other tasks ready to run
idle_task:
        in tmp, _SFR_IO_ADDR(PORTD)
        inc tmp
        out _SFR_IO_ADDR(PORTD), tmp
        rjmp idle_task

        
        ;; schedule next task and process system clock and task timers,
        ;; driven by hardware interruption
        .global TIMER0_COMP_vect
TIMER0_COMP_vect:
        save                                    ; save task execution context
        rcall timers                            ; process timers
        rcall inc_time                          ; increase system time
        ldi tmp, TASK_RUNNING                   ; load task state to tmp
        ldi tmp2, TASK_STATE                    ; load task struct offset to tmp2
        rcall find                              ; find next task to run 
        rcall switch                            ; switch to next task
        oci_enable                              ; enable output compare interrupt
        in tmp, _SFR_IO_ADDR(TCNT0)             ; load current timer value
        subi tmp, (-TCNT_ADD)                   ; add scheduler interval
        out _SFR_IO_ADDR(OCR0), tmp             ; store compare register value
        restore                                 ; restore task execution context
        reti                                    ; enable interrupts and execute task

        
        ;; schedule next task explicitly
        .global schedule
schedule:
        save                                    ; save task execution context
        ldi tmp, TASK_RUNNING                   ; load task state to tmp
        ldi tmp2, TASK_STATE                    ; load task struct offset to tmp2
        rcall find                              ; find next task to run 
        rcall switch                            ; switch to next task
        restore                                 ; restore task execution context
        reti                                    ; enable interrupts and execute task
        
        
        ;; get value of scheduler tick counter
        .global get_time
get_time:
        lds ret3, sys_time                      ; load first byte
        lds ret4, sys_time + 1                  ; load second byte
        lds ret1, sys_time + 2                  ; load third byte
        lds ret2, sys_time + 3                  ; load fourth byte
        reti


        ;; create new task
        .global create
create:
        ATOMIC_BEGIN                            ; begin atomic block
        ldi tmp, TASK_KILLED                    ; load task state to tmp
        ldi tmp2, TASK_STATE                    ; load task struct offset to tmp2
        rcall find                              ; find free task slot
        ldi tmp2, hi8(TASK_ADDR_IDLE)           ; check task address
        cpi ZL, lo8(TASK_ADDR_IDLE)             ; compare lower byte of task address
        cpc ZH, tmp2                            ; compare upper byte of task address
        breq create_1                           ; step over
        mov XL, ZL                              ; copy address of task to X
        mov XH, ZH                              ;
        ;; add offset to top of stack of task, preserve space for execution context and return address
        addiw XL, XH, TASK_STACK_BOTTOM - TASK_CONTEXT_SIZE
        std Z + TASK_STACK_PTR, XL              ; store address to stack pointer of task
        std Z + TASK_STACK_PTR + 1, XH          ;
        addiw ZL, ZH, (TASK_STACK_BOTTOM - 1)   ; move Z to upper byte of return address
        st Z, arg2                              ; store upper byte of return address
        std Z + 1, arg1                         ; store lower byte of return address
        addiw ZL, ZH, -(TASK_STACK_BOTTOM - 1)  ; move Z back to task address
        stdi Z + TASK_STATE, TASK_RUNNING, tmp  ; wake up task
        ldd ret1, Z + TASK_ID                   ; load id of task to ret1
        clr ret2                                ; clear ret2
        ATOMIC_END                              ; end atomic block
create_1: 
        ldiw ret1, ret2, RET_NOAVAIL            ; load RET_NOAVAIL to ret
        ATOMIC_END                              ; end atomic block

        
        ;; create idle task
create_idle:
        ldiw ZL, ZH, TASK_ADDR_IDLE             ; load address of idle task to Z
        ldiw XL, XH, TASK_ADDR_IDLE             ; load address of idle task to X
        ;; add offset to top of stack of task, preserve space for execution context and return address
        addiw XL, XH, TASK_STACK_BOTTOM - TASK_CONTEXT_SIZE
        std Z + TASK_STACK_PTR, XL              ; store address to stack pointer of task
        std Z + TASK_STACK_PTR + 1, XH          ;
        addiw ZL, ZH, (TASK_STACK_BOTTOM - 1)   ; move Z to upper byte of return address
        sti Z, hi8(gs(idle_task)), tmp          ; store upper byte of idle task address
        stdi Z + 1, lo8(gs(idle_task)), tmp     ; store lower byte of idle task address
        addiw ZL, ZH, -(TASK_STACK_BOTTOM - 1)  ; move Z back to task address
        stdi Z + TASK_STATE, TASK_RUNNING, tmp  ; wake up task
        ret
        

        ;; end task
        .global exit
exit:
        cli                                     ; begin atomic block
        lds ZL, task_addr                       ; load address of current task to Z
        lds ZH, task_addr + 1                   ;
        stdi Z + TASK_STATE, TASK_KILLED, tmp   ; kill task
        stdi Z + TASK_LOCK, 0, tmp              ; clear lock number
        rjmp schedule                           ; schedule next task


        ;; get id of current task
        .global get_id
get_id:
        ATOMIC_BEGIN                            ; begin atomic block
        lds ZL, task_addr                       ; load address of current task to Z
        lds ZH, task_addr + 1                   ;
        ldd ret1, Z + TASK_ID                   ; load id of task to ret1
        clr ret2                                ; clear ret2
        ATOMIC_END                              ; end atomic block


        ;; wait for signal from other task or scheduler
        .global sleep
sleep:
        ATOMIC_BEGIN                            ; begin atomic block
        lds ZL, task_addr                       ; load address of current task to Z
        lds ZH, task_addr + 1                   ;
        std Z + TASK_TIMER, arg1                ; store timer value
        std Z + TASK_TIMER + 1, arg2            ; 
        stdi Z + TASK_STATE, TASK_SLEEPING, tmp ; suspend task
        rcall schedule                          ; schedule next task
        ldd XL, Z + TASK_TIMER                  ; load timer value
        ldd XH, Z + TASK_TIMER + 1              ; 
        ldi tmp2, 0                             ; check if timer value is zero
        cpi XL, 0                               ; compare lower byte
        cpc XH, tmp2                            ; compare upper byte
        breq sleep_2                            ; step over if zero
        mov ret1, XL                            ; copy remaining value of timer to ret
        mov ret2, XH                            ;
        ATOMIC_END                              ; end atomic block
sleep_2: 
        ldiw ret1, ret2, 666
        ATOMIC_END                              ; end atomic block
        

        ;; send signal to task with matching id
.global signal
signal:
        ATOMIC_BEGIN                            ; begin atomic block
        mov tmp, arg1                           ; copy task id to tmp
        ldi tmp2, TASK_ID                       ; copy task struct offset to tmp2
        rcall find                              ; find task with matching id
        ldi tmp2, hi8(TASK_ADDR_IDLE)           ; check task address
        cpi ZL, lo8(TASK_ADDR_IDLE)             ; compare lower byte of task address
        cpc ZH, tmp2                            ; compare upper byte of task address
        breq signal_6                           ; step over
        ldd tmp, Z + TASK_STATE                 ; load task state
        cpi tmp, TASK_KILLED                    ; check if task is alive
        breq signal_6                           ; 
        cpi arg3, SIG_KILL                      ; check if SIG_KILL
        breq signal_1                           ; 
        cpi arg3, SIG_STOP                      ; check if SIG_STOP
        breq signal_2                           ; 
        cpi arg3, SIG_CONT                      ; check if SIG_CONT
        breq signal_3                           ; 
        cpi arg3, SIG_STAT                      ; check if SIG_STAT
        breq signal_4                           ; 
        rjmp signal_5                           ; no valid signal, invalid argument
signal_1:
        stdi Z + TASK_STATE, TASK_KILLED, tmp   ; kill task
        ldiw ret1, ret2, RET_OK                 ; load RET_OK to ret
        ATOMIC_END                              ; end atomic block
signal_2:
        stdi Z + TASK_STATE, TASK_STOPPED, tmp  ; suspend task
        ldiw ret1, ret2, RET_OK                 ; load RET_OK to ret
        ATOMIC_END                              ; end atomic block
signal_3:
        stdi Z + TASK_STATE, TASK_RUNNING, tmp  ; wake up task
        ldiw ret1, ret2, RET_OK                 ; load RET_OK to ret
        ATOMIC_END                              ; end atomic block
signal_4:
        ldd ret1, Z + TASK_STATE                ; load task state to ret1
        clr ret2                                ; clear ret2
        ATOMIC_END                              ; end atomic block
signal_5:
        ldiw ret1, ret2, RET_INVAL              ; load RET_INVAL to ret
        ATOMIC_END                              ; end atomic block
signal_6:
        ldiw ret1, ret2, RET_NOEXIST            ; load RET_NOEXIST to ret
        ATOMIC_END                              ; end atomic block


        ;; wait for semaphore
        .global sem_wait
sem_wait: 
        ATOMIC_BEGIN                            ; begin atomic block
        cpi arg1, SEM_CNT                       ; bound check semaphore number
        brsh sem_wait_3                         ; step over if out of bound
        mov ZL, arg1                            ; load semaphore number to Z
        clr ZH                                  ; 
        addiw ZL, ZH, semaphores                ; add address of semaphore array
        ld tmp, Z                               ; load value of semaphore
        cpi arg3, 0                             ; check if blocking wait (argument is zero)
        breq sem_wait_1                         ; step over if blocking wait
        cpi tmp, 0                              ; check if semaphore already locked (negative value)
        brmi sem_wait_5                         ; step over if already locked
sem_wait_1:
        dec tmp                                 ; decrease value of semaphore
        st Z, tmp                               ; store new value of semaphore
        brpl sem_wait_2                         ; step over if semaphore is not locked (positive value)
        lds ZL, task_addr                       ; load address of current task to Z
        lds ZH, task_addr + 1                   ;
        stdi Z + TASK_STATE, TASK_SLEEPING, tmp2 ; suspend task 
        mov tmp2, arg1                          ; copy semaphore number to tmp
        subi tmp2, (-LOCK_SEM)                  ; add semaphore lock offset
        std Z + TASK_LOCK, tmp2                 ; store lock number
        rcall schedule                          ; schedule next task
        ldd tmp2, Z + TASK_LOCK                 ; load lock number
        cpi tmp2, 0                             ; check if interrupted by signal
        brne sem_wait_4                         ; step over if interrupted
sem_wait_2: 
        ldiw ret1, ret2, RET_OK                 ; load RET_OK to ret
        ATOMIC_END                              ; end atomic block
sem_wait_3:
        ldiw ret1, ret2, RET_INVAL              ; load RET_INVAL to ret
        ATOMIC_END                              ; end atomic block
sem_wait_4:
        ldiw ret1, ret2, RET_INTR               ; load RET_INTR to ret
        ATOMIC_END                              ; end atomic block
sem_wait_5:
        ldiw ret1, ret2, RET_LOCKED             ; load RET_LOCKED to ret
        ATOMIC_END                              ; end atomic block


        ;; post to semaphore
        .global sem_post
sem_post:
        ATOMIC_BEGIN                            ; begin atomic block
        cpi arg1, SEM_CNT                       ; bound check semaphore number
        brsh sem_post_3                         ; step over
        cpi arg3, 1                             ; check increment count, must be at least one
        brlo sem_post_3                         ; step over
        mov ZL, arg1                            ; store semaphore number to Z
        clr ZH                                  ; 
        addiw ZL, ZH, semaphores                ; add address of semaphore array
        ld tmp, Z                               ; load value of semaphore
        add tmp, arg3                           ; increase value of semaphore
        st Z, tmp                               ; store new value of semaphore
        mov tmp, arg1                           ; copy argument to tmp
        subi tmp, (-LOCK_SEM)                   ; add semaphore lock offset
        ldi tmp2, TASK_LOCK                     ; load task struct offset to tmp2
        rcall find                              ; find task waiting for semaphore
        ldi tmp2, hi8(TASK_ADDR_IDLE)           ; check task address
        cpi ZL, lo8(TASK_ADDR_IDLE)             ; compare lower byte of task address
        cpc ZH, tmp2                            ; compare upper byte of task address
        breq sem_post_2                         ; step over
        stdi Z + TASK_STATE, TASK_RUNNING, tmp  ; wake up task
        stdi Z + TASK_LOCK, 0, tmp              ; clear lock number
sem_post_2:
        ldiw ret1, ret2, RET_OK                 ; load RET_OK to ret
        ATOMIC_END                              ; end atomic block
sem_post_3:
        ldiw ret1, ret2, RET_INVAL              ; load RET_INVAL to ret
        ATOMIC_END                              ; end atomic block


        ;; get semaphore value
        .global sem_get
sem_get:
        ATOMIC_BEGIN                            ; begin atomic block
        cpi arg1, SEM_CNT                       ; bound check semaphore number
        brsh sem_get_1                          ; step over
        mov ZL, arg1                            ; copy semaphore number to Z
        clr ZH                                  ;
        addiw ZL, ZH, semaphores                ; add address of semaphore array
        ld ret1, Z                              ; load value of semaphore to ret1
        clr ret2                                ; clear ret2
        ATOMIC_END                              ; end atomic block
sem_get_1:
        ldiw ret1, ret2, RET_INVAL              ; load RET_INVAL to ret
        ATOMIC_END                              ; end atomic block


        ;; lock mutex
mtx_lock: 
        ATOMIC_BEGIN                            ; begin atomic block
        cpi arg1, MTX_CNT                       ; bound check mutex number
        brsh mtx_lock_3                         ; step over if out of bound
        lds ZL, task_addr                       ; load address of current task to Z
        lds ZH, task_addr + 1                   ;
        ldd tmp2, Z + TASK_ID                   ; load task id
        mov ZL, arg1                            ; copy mutex number to Z
        clr ZH                                  ;
        addiw ZL, ZH, mutexes                   ; add address of mutex array
        ld tmp, Z                               ; load value of mutex
        cpi arg3, 0                             ; check if blocking wait (argument is zero)
        breq mtx_lock_1                         ; step over if blocking wait
        cpi tmp, 0                              ; check if mutex is already locked
        brne mtx_lock_5                         ; step over if already locked
mtx_lock_1:
        cpi tmp, 0                              ; check if mutex is locked
        breq mtx_lock_2                         ; step over if not locked
        lds ZL, task_addr                       ; load address of current task to Z
        lds ZH, task_addr + 1                   ; 
        stdi Z + TASK_STATE, TASK_SLEEPING, tmp2 ; suspend task 
        mov tmp2, arg1                          ; copy mutex number to tmp
        subi tmp2, (-LOCK_MTX)                  ; add mutex lock offset
        std Z + TASK_LOCK, tmp2                 ; store lock number
        rcall schedule                          ; schedule next task
        ldd tmp2, Z + TASK_LOCK                 ; load lock number
        cpi tmp2, 0                             ; check if interrupted by signal
        brne mtx_lock_4                         ; step over if interrupted
        ldiw ret1, ret2, RET_OK                 ; load RET_OK to ret
        ATOMIC_END                              ; end atomic block
mtx_lock_2: 
        st Z, tmp2                              ; lock mutex, current task is owner of lock
        ldiw ret1, ret2, RET_OK                 ; load RET_OK to ret
        ATOMIC_END                              ; end atomic block
mtx_lock_3:
        ldiw ret1, ret2, RET_INVAL              ; load RET_INVAL to ret
        ATOMIC_END                              ; end atomic block
mtx_lock_4:
        stdi Z + TASK_LOCK, 0, tmp              ; clear lock index
        ldiw ret1, ret2, RET_INTR               ; load RET_INTR to ret
        ATOMIC_END                              ; end atomic block
mtx_lock_5:
        ldiw ret1, ret2, RET_LOCKED             ; load RET_LOCKED to ret
        ATOMIC_END                              ; end atomic block
        .global mtx_lock

        
        ;; unlock mutex
        .global mtx_unlock
mtx_unlock: 
        ATOMIC_BEGIN                            ; begin atomic block
        cpi arg1, MTX_CNT                       ; bound check mutex number
        brsh mtx_unlock_3                       ; step over
        lds ZL, task_addr                       ; load address of current task to Z
        lds ZH, task_addr + 1                   ;
        ldd tmp2, Z + TASK_ID                   ; load task id
        mov ZL, arg1                            ; copy mutex number to Z
        clr ZH                                  ; 
        addiw ZL, ZH, mutexes                   ; add address of mutex array
        ld tmp, Z                               ; load value of mutex
        cpi tmp, 0                              ; check if mutex is already unlocked
        breq mtx_unlock_2                       ; step over if unlocked
        cp tmp, tmp2                            ; check if mutex if locked by this task
        ;; step over if not locked by this task (locked by other task, operation not permitted)
        brne mtx_unlock_4
        sti Z, 0, tmp                           ; unlock mutex, not owned by any task (zero value)
        mov tmp, arg1                           ; copy argument to tmp
        subi tmp, (-LOCK_MTX)                   ; add mutex lock offset
        ldi tmp2, TASK_LOCK                     ; load task struct offset to tmp2
        rcall find                              ; find task waiting for mutex
        ldi tmp2, hi8(TASK_ADDR_IDLE)           ; check task address
        cpi ZL, lo8(TASK_ADDR_IDLE)             ; compare lower byte of task address
        cpc ZH, tmp2                            ; compare upper byte of task address
        breq mtx_unlock_2                       ; step over
        stdi Z + TASK_STATE, TASK_RUNNING, tmp  ; wake up task
        stdi Z + TASK_LOCK, 0, tmp              ; clear lock index
mtx_unlock_2:
        ldiw ret1, ret2, RET_OK                 ; load RET_OK to ret
        ATOMIC_END                              ; end atomic block
mtx_unlock_3:
        ldiw ret1, ret2, RET_INVAL              ; load RET_INVAL to ret
        ATOMIC_END                              ; end atomic block
mtx_unlock_4:
        ldiw ret1, ret2, RET_PERM               ; load RET_PERM to ret
        ATOMIC_END                              ; end atomic block
        
        ;; required for initialization of data segment
        .global __do_copy_data
