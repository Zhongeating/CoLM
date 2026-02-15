#include <define.h>

MODULE MOD_SPMD_Task_CUDA

   USE MOD_SPMD_Task

   IMPLICIT NONE

CONTAINS

   ! -- STOP all processes --
   attributes(device) SUBROUTINE CoLM_stop_CUDA (mesg)

   IMPLICIT NONE
   character(len=*), optional :: mesg

   STOP

   END SUBROUTINE CoLM_stop_CUDA

END MODULE MOD_SPMD_Task_CUDA
