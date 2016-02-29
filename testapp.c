#include <avr/io.h>
#include "avros.h"

void signal_test();
void mutex_test();
void semaphore_test();

#define SIGNAL_TEST 1
#define MUTEX_TEST 2
#define SEMAPHORE_TEST 3

int main()
{
        /* port a and b are outputs */
        DDRA = 0xff;
        DDRB = 0xff;
        DDRD = 0xff;


        int testnum = SIGNAL_TEST;
        switch (testnum)
        {
        case SIGNAL_TEST:
                /* init operating system with signal_test entry point */
                init(signal_test);
                break;
        case MUTEX_TEST:
                /* init operating system with mutex_test entry point */
                init(mutex_test);
                break;
        case SEMAPHORE_TEST:
                /* init operating system with semaphore_test entry point */
                init(semaphore_test);
                break;
        default:
                break;
        }
        return 0;
}


