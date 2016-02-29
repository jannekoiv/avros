/*
This program creates two tasks which are both running their own instance of subroutine mutex_test_var.
Global variable mutex_test_var is initialized to value 20015. Both instances of subroutine decrement
value of mutex_test_var for 10000 times. When both tasks are finished, value of variable should be 15.
Main routine mutex_test waits until both tasks are finished and then outputs the variable to port a.
Decrementing is protected by critical section implemented with mutex. Only one tasks can enter
the critical section at one time. When other task tries to enter the critical section by calling
mtx_lock, it will be suspended until other task that is currently in critical section leaves it
by calling mtx_unlock. Mutex protection can by commenting out MUTEX_LOCK. Mutex can also be replaced
with semaphore by commenting out MUTEX_LOCK and uncommenting SEMAPHORE_LOCK.
*/

#include <avr/io.h>
#include "avros.h"
#define MUTEX_LOCK
/* #define SEMAPHORE_LOCK */

int mutex_test_var = 20015;

void mutex_test_task()
{
        /* decrease variable 10000 times */
        int i = 0;
        while (i < 10000)
        {
                i ++;
                #ifdef MUTEX_LOCK
                mtx_lock(0, 0); /* enter critical section */
                #endif
                #ifdef SEMAPHORE_LOCK
                sem_wait(0, 0); /* enter critical section */
                #endif
                mutex_test_var --; /* decrement variable */
                #ifdef MUTEX_LOCK
                mtx_unlock(0);  /* leave critical section */
                #endif
                #ifdef SEMAPHORE_LOCK
                sem_post(0, 1);  /* leave critical section */
                #endif
        }
        exit();                 /* terminate task */
}

void mutex_test()
{
        /* port a is output */
        DDRA = 0xff;
        /* create two tasks running same code */
        unsigned char id1 = create(mutex_test_task);  
        unsigned char id2 = create(mutex_test_task);
        /* wait until both tasks are terminated */
        while (signal(id1, SIG_STAT) != RET_NOEXIST ||
               signal(id2, SIG_STAT) != RET_NOEXIST) {}
        /* output variable to port a, should be 15 (00001111) */
        PORTA = mutex_test_var;
        /* sit in loop */
        while(1) {}
}


