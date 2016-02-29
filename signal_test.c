/*
This program creates fours tasks running same code and synchronizes them using signals. Only one
of tasks is running at each time. Task rises one bit indicating it's id in port a and then sleeps
for 100 scheduler ticks. When task has slept for 100 ticks, it wakes up next task and suspend itself
until previous task wakes it with signal. So task execution order is 0, 1, 2, 3, 0, 1, 2, 3, etc.
Main task creates four tasks, stores their identifiers to array and then wakes up first of them.
Then it sleeps for 5000 scheduler ticks, kills all four tasks and rises four upper bits in port a
indicating end of program.
*/

#include <avr/io.h>
#include "avros.h"

char tasks[4];                  /* identifiers of test tasks */
char main_task = 0;             /* identifier of main task */

#define TASK_COUNT 4

void signal_task()
{
        static char task_cnt = 0; /* static task count variable, shared between all tasks */
        char task_num = task_cnt; /* local task number (index) variable */
        task_cnt ++;              /* increase shared task count variable */
        signal(main_task, SIG_CONT); /* signal main task that task has initialized */
        sleep(0);                    /* sleep until waken by other task */
        while (1)
        {
                PORTA = 1 << task_num; /* indicate task number by rising corresponding bit in port a */
                sleep(100);           /* sleep for 1000 scheduler ticks */
                /* calculate number of next task */
                int task_next = task_num + 1;
                if (task_next == TASK_COUNT)
                {
                        task_next = 0;
                }
                /* wake up next task and sleep until waken by other task */
                signal(tasks[task_next], SIG_CONT);
                sleep(0);
        }
}

void signal_test()
{
        /* port a is output */
        DDRA = 0xff;
        main_task = get_id();   /* get id of main task */
        int i = 0;
        for (i = 0; i < TASK_COUNT; i ++)
        {
                tasks[i] = create(signal_task); /* create task */
                sleep(0);                       /* wait until task has initialized */
        }
        /* wake up first task */
        signal(tasks[0], SIG_CONT);
        /* sleep for 10000 scheduler ticks */
        sleep(5000);
        /* kill all tasks */
        for (i = 0; i < TASK_COUNT; i ++)
        {
                signal(tasks[i], SIG_KILL);
        }
        /* rise four upper bits in port a */
        PORTA |= 0xf0;
        /* sit in loop */
        while(1) {}
}
