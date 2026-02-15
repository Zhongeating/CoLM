#include <define.h>

MODULE MOD_Aerosol_CUDA

!-----------------------------------------------------------------------
   USE cudafor
   USE MOD_ConstVars_CUDA

   USE MOD_Precision
   USE MOD_Grid
   USE MOD_DataType
   USE MOD_SpatialMapping
   IMPLICIT NONE
   SAVE

! PUBLIC MEMBER FUNCTIONS:
   PUBLIC :: AerosolMasses

! PUBLIC DATA MEMBERS:
!-----------------------------------------------------------------------

   logical,  parameter :: use_extrasnowlayers = .false.
   real(r8), parameter :: snw_rds_min = 54.526_r8          ! minimum allowed snow effective radius (also "fresh snow" value) [microns]
   real(r8), parameter :: fresh_snw_rds_max = 204.526_r8   ! maximum warm fresh snow effective radius [microns]

   character(len=256)  :: file_aerosol

   type(grid_type) :: grid_aerosol
   type(block_data_real8_2d)  :: f_aerdep
   type(spatial_mapping_type) :: mg2p_aerdep

   integer, parameter :: start_year = 1849
   integer, parameter :: end_year   = 2001

   integer :: month_p

CONTAINS

   attributes(device) SUBROUTINE AerosolMasses( dtime         ,snl            ,do_capsnow    ,&
              h2osno_ice    ,h2osno_liq    ,qflx_snwcp_ice ,snw_rds       ,&

              mss_bcpho     ,mss_bcphi     ,mss_ocpho      ,mss_ocphi     ,&
              mss_dst1      ,mss_dst2      ,mss_dst3       ,mss_dst4      ,&

              mss_cnc_bcphi ,mss_cnc_bcpho ,mss_cnc_ocphi  ,mss_cnc_ocpho ,&
              mss_cnc_dst1  ,mss_cnc_dst2  ,mss_cnc_dst3   ,mss_cnc_dst4  )

!-----------------------------------------------------------------------
! !DESCRIPTION:
!  Calculate column-integrated aerosol masses, and
!  mass concentrations for radiative calculations and output
!  (based on new snow level state, after SnowFilter is rebuilt.
!  NEEDS TO BE AFTER SnowFiler is rebuilt in Hydrology2, otherwise there
!  can be zero snow layers but an active column in filter)
!-----------------------------------------------------------------------

   IMPLICIT NONE

   ! !ARGUMENTS:
   !
   real(r8),intent(in)     ::  dtime            !  seconds in a time step [second]
   integer, intent(in)     ::  snl              !  number of snow layers

   logical,  intent(in)    ::  do_capsnow       !  true => do snow capping
   real(r8), intent(in)    ::  h2osno_ice    ( maxsnl+1:0 ) !  ice lens (kg/m2)
   real(r8), intent(in)    ::  h2osno_liq    ( maxsnl+1:0 ) !  liquid water (kg/m2)
   real(r8), intent(in)    ::  qflx_snwcp_ice   !  excess snowfall due to snow capping (mm H2O /s) [+]

   real(r8), intent(inout) ::  snw_rds       ( maxsnl+1:0 ) !  effective snow grain radius (col,lyr) [microns, m^-6]

   real(r8), intent(inout) ::  mss_bcpho     ( maxsnl+1:0 ) !  mass of hydrophobic BC in snow (col,lyr) [kg]
   real(r8), intent(inout) ::  mss_bcphi     ( maxsnl+1:0 ) !  mass of hydrophillic BC in snow (col,lyr) [kg]
   real(r8), intent(inout) ::  mss_ocpho     ( maxsnl+1:0 ) !  mass of hydrophobic OC in snow (col,lyr) [kg]
   real(r8), intent(inout) ::  mss_ocphi     ( maxsnl+1:0 ) !  mass of hydrophillic OC in snow (col,lyr) [kg]
   real(r8), intent(inout) ::  mss_dst1      ( maxsnl+1:0 ) !  mass of dust species 1 in snow (col,lyr) [kg]
   real(r8), intent(inout) ::  mss_dst2      ( maxsnl+1:0 ) !  mass of dust species 2 in snow (col,lyr) [kg]
   real(r8), intent(inout) ::  mss_dst3      ( maxsnl+1:0 ) !  mass of dust species 3 in snow (col,lyr) [kg]
   real(r8), intent(inout) ::  mss_dst4      ( maxsnl+1:0 ) !  mass of dust species 4 in snow (col,lyr) [kg]

   real(r8), intent(out)   ::  mss_cnc_bcphi ( maxsnl+1:0 ) !  mass concentration of BC species 1 (col,lyr) [kg/kg]
   real(r8), intent(out)   ::  mss_cnc_bcpho ( maxsnl+1:0 ) !  mass concentration of BC species 2 (col,lyr) [kg/kg]
   real(r8), intent(out)   ::  mss_cnc_ocphi ( maxsnl+1:0 ) !  mass concentration of OC species 1 (col,lyr) [kg/kg]
   real(r8), intent(out)   ::  mss_cnc_ocpho ( maxsnl+1:0 ) !  mass concentration of OC species 2 (col,lyr) [kg/kg]
   real(r8), intent(out)   ::  mss_cnc_dst1  ( maxsnl+1:0 ) !  mass concentration of dust species 1 (col,lyr) [kg/kg]
   real(r8), intent(out)   ::  mss_cnc_dst2  ( maxsnl+1:0 ) !  mass concentration of dust species 2 (col,lyr) [kg/kg]
   real(r8), intent(out)   ::  mss_cnc_dst3  ( maxsnl+1:0 ) !  mass concentration of dust species 3 (col,lyr) [kg/kg]
   real(r8), intent(out)   ::  mss_cnc_dst4  ( maxsnl+1:0 ) !  mass concentration of dust species 4 (col,lyr) [kg/kg]

   ! !LOCAL VARIABLES:
   integer  :: c,j             ! indices
   real(r8) :: snowmass        ! liquid+ice snow mass in a layer [kg/m2]
   real(r8) :: snowcap_scl_fct ! temporary factor used to correct for snow capping

      !-----------------------------------------------------------------------

      DO j = maxsnl+1, 0

         ! layer mass of snow:
         snowmass = h2osno_ice(j) + h2osno_liq(j)

         IF (.not. use_extrasnowlayers) THEN
            ! Correct the top layer aerosol mass to account for snow capping.
            ! This approach conserves the aerosol mass concentration
            ! (but not the aerosol mass) when snow-capping is invoked

            IF (j == snl+1) THEN
               IF (do_capsnow) THEN

                  snowcap_scl_fct = snowmass / (snowmass + (qflx_snwcp_ice*dtime))

                  mss_bcpho(j) = mss_bcpho(j)*snowcap_scl_fct
                  mss_bcphi(j) = mss_bcphi(j)*snowcap_scl_fct
                  mss_ocpho(j) = mss_ocpho(j)*snowcap_scl_fct
                  mss_ocphi(j) = mss_ocphi(j)*snowcap_scl_fct

                  mss_dst1(j)  = mss_dst1(j)*snowcap_scl_fct
                  mss_dst2(j)  = mss_dst2(j)*snowcap_scl_fct
                  mss_dst3(j)  = mss_dst3(j)*snowcap_scl_fct
                  mss_dst4(j)  = mss_dst4(j)*snowcap_scl_fct
               ENDIF
            ENDIF
         ENDIF

         IF (j >= snl+1) THEN

            mss_cnc_bcphi(j) = mss_bcphi(j) / snowmass
            mss_cnc_bcpho(j) = mss_bcpho(j) / snowmass

            mss_cnc_ocphi(j) = mss_ocphi(j) / snowmass
            mss_cnc_ocpho(j) = mss_ocpho(j) / snowmass

            mss_cnc_dst1(j)  = mss_dst1(j)  / snowmass
            mss_cnc_dst2(j)  = mss_dst2(j)  / snowmass
            mss_cnc_dst3(j)  = mss_dst3(j)  / snowmass
            mss_cnc_dst4(j)  = mss_dst4(j)  / snowmass

         ELSE
            ! 01/10/2023, yuan: set empty snow layers to snw_rds_min
            !snw_rds(j)       = 0._r8
            snw_rds(j)       = snw_rds_min

            mss_bcpho(j)     = 0._r8
            mss_bcphi(j)     = 0._r8
            mss_cnc_bcphi(j) = 0._r8
            mss_cnc_bcpho(j) = 0._r8

            mss_ocpho(j)     = 0._r8
            mss_ocphi(j)     = 0._r8
            mss_cnc_ocphi(j) = 0._r8
            mss_cnc_ocpho(j) = 0._r8

            mss_dst1(j)      = 0._r8
            mss_dst2(j)      = 0._r8
            mss_dst3(j)      = 0._r8
            mss_dst4(j)      = 0._r8
            mss_cnc_dst1(j)  = 0._r8
            mss_cnc_dst2(j)  = 0._r8
            mss_cnc_dst3(j)  = 0._r8
            mss_cnc_dst4(j)  = 0._r8
         ENDIF
      ENDDO

   END SUBROUTINE AerosolMasses

END MODULE MOD_Aerosol_CUDA
