/*
This program creates three tasks and synchronizes them using two semaphores. Two of tasks are so
called consumer tasks that wait for new data from third producer task and outputs it to ports a and b.
Both semaphores are initialized to value one when operating system is initialized. When consumer task
calls for sem_wait, value of semaphore is decremented by one. When value of semaphore becomes negative,
task will be suspended until other task (producer) calls for sem_post which increments value of semaphore
and wakes up task that is waiting for semaphore. Producer task stores new values into global variables
data_1 and data_2 and posts to semaphore zero and one. Consumer tasks wait for semaphore and outputs
value of variable each time when producer task posts to corresponding semaphore.
*/

#include <avr/io.h>
#include "avros.h"

unsigned char data_1 = 0;
unsigned char data_2 = 0;

void semaphore_consumer_1()
{
        while(1)
        {
                sem_wait(0, 0);          /* wait for semaphore 0 */
                PORTA = data_1;          /* output data to port a */
        }
}

void semaphore_consumer_2()
{
        while(1)
        {
                sem_wait(1, 0);          /* wait for semaphore 1 */
                PORTB = data_2;          /* output data to port b */
        }
}

void semaphore_producer()
{
        while(1)
        {
                data_1 ++;           /* prepare data for consumer 1  */
                sem_post(0, 1);      /* post to semaphore 0 (increase it's value) */
                sleep(100);          /* sleep for 100 scheduler ticks */
                data_2 += 4;         /* prepare data for consumer 2 */
                sem_post(1, 1);      /* post to semaphore 1 (increase it's value) */
                sleep(100);          /* sleep for 100 scheduler ticks */
        }
}

void semaphore_test()
{
        /* ports a and b are outputs */
        DDRA = 0xff;
        DDRB = 0xff;
        /* create consumer task 1. consumer waits for data from producer by waiting for semaphore. */
        create(semaphore_consumer_1);
        /* create consumer task 2. consumer waits for data from producer by waiting for semaphore. */
        create(semaphore_consumer_2);
        /* create producer task. producer produces data and signals consumer by posting to semaphore. */
        create(semaphore_producer);
        /* sit in loop */
        while(1) {}
}
