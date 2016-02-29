#define CPU_FREQ 16000000       /* cpu clock frequency (Hz) */
#define SCHED_FREQ 1000         /* scheduler frequency (Hz) */

#define TASK_CNT 5              /* number of processes */
#define STACK_SIZE 200          /* size of stack in bytes */

#define SEM_CNT 5               /* number of semaphores */
#define MTX_CNT 5               /* number of mutexes */

#define TASK_KILLED 0           /* task is killed */
#define TASK_RUNNING 1          /* task is running */
#define TASK_STOPPED 2          /* task is stopped (by sending stop signal) */
#define TASK_SLEEPING 3         /* task is sleeping (waiting for signal, timer, semaphore or mutex) */

#define SIG_STAT 0              /* ask state of process, can be used for checking if task exists */
#define SIG_KILL 1              /* kill task */
#define SIG_STOP 2              /* stop task */
#define SIG_CONT 3              /* continue task */

#define RET_OK 0                /* no error */
#define RET_INVAL -128          /* invalid argument */ 
#define RET_LOCKED -127         /* semaphore or mutex is already locked */
#define RET_INTR -126           /* lock was interrupted by signal */
#define RET_NOEXIST -125        /* resource not found */
#define RET_NOAVAIL -124        /* resource not available */
#define RET_PERM -123           /* operation not permitted */


