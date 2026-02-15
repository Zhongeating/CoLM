#include <define.h>

MODULE MOD_Init_CUDA

   USE cudafor
   USE MOD_SPMD_Task_CUDA
   USE MOD_ConstVars_CUDA

   IMPLICIT NONE

   integer, parameter :: blockDim1 = 256
   integer, parameter :: blockDim2 = 8
   integer, parameter :: blockDim3 = 4
   integer :: ierr

   INTERFACE calendarday_cuda
      MODULE procedure calendarday_date_cuda
      MODULE procedure calendarday_stamp_cuda
   END INTERFACE

CONTAINS

   attributes(device) real(r8) FUNCTION calendarday_date_cuda(date)

   IMPLICIT NONE
   integer, intent(in) :: date(3)

   integer idate(3)

      idate(:) = date(:)

      IF ( .not. d_isgreenwich ) THEN
         CALL localtime2gmt_cuda(idate)
      ENDIF

      calendarday_date_cuda = (idate(2)) + (idate(3))/86400.
      RETURN

   END FUNCTION calendarday_date_cuda

   attributes(device) real(r8) FUNCTION calendarday_stamp_cuda(stamp)

   IMPLICIT NONE
   type(timestamp), intent(in) :: stamp

   integer idate(3)

      idate(1) = stamp%year
      idate(2) = stamp%day
      idate(3) = stamp%sec

      IF ( .not. d_isgreenwich ) THEN
         CALL localtime2gmt_cuda(idate)
      ENDIF

      calendarday_stamp_cuda = (idate(2)) + (idate(3))/86400.
      RETURN

   END FUNCTION calendarday_stamp_cuda

   attributes(device) SUBROUTINE localtime2gmt_cuda(idate)

   IMPLICIT NONE
   integer, intent(inout) :: idate(3)

   integer  maxday
   real(r8) tdiff

      tdiff = d_LocalLongitude/15.*3600.
      idate(3) = idate(3) - int(tdiff)

      IF (idate(3) < 0) THEN

         idate(3) = 86400 + idate(3)
         idate(2) = idate(2) - 1

         IF (idate(2) < 1) THEN
            idate(1) = idate(1) - 1
            IF ( isleapyear_cuda(idate(1)) ) THEN
               idate(2) = 366
            ELSE
               idate(2) = 365
            ENDIF
         ENDIF
      ENDIF

      IF (idate(3) > 86400) THEN

         idate(3) = idate(3) - 86400
         idate(2) = idate(2) + 1

         IF ( isleapyear_cuda(idate(1)) ) THEN
            maxday = 366
         ELSE
            maxday = 365
         ENDIF

         IF(idate(2) > maxday) THEN
            idate(1) = idate(1) + 1
            idate(2) = 1
         ENDIF
      ENDIF

   END SUBROUTINE localtime2gmt_cuda

   attributes(device) logical FUNCTION isleapyear_cuda(year)

   IMPLICIT NONE
   integer, intent(in) :: year

      IF( (mod(year,4)==0 .and. mod(year,100)/=0) .or. &
         mod(year,400)==0 ) THEN
         isleapyear_cuda = .true.
      ELSE
         isleapyear_cuda = .false.
      ENDIF
      RETURN
   END FUNCTION isleapyear_cuda

END MODULE MOD_Init_CUDA
