#include <define.h>
MODULE MOD_LeafInterception_CUDA
! -----------------------------------------------------------------
! !DESCRIPTION:
! For calculating vegetation canopy preciptation interception.
!
! This MODULE is the coupler for the colm and CaMa-Flood model.

!ANCILLARY FUNCTIONS AND SUBROUTINES
!-------------------
   !* :SUBROUTINE:"LEAF_interception_CoLM2014"   : interception and drainage of precipitation schemes based on colm2014 version
   !* :SUBROUTINE:"LEAF_interception_CoLM202x"   : interception and drainage of precipitation schemes besed on new colm version (under development)
   !* :SUBROUTINE:"LEAF_interception_CLM4"       : interception and drainage of precipitation schemes modified from CLM4
   !* :SUBROUTINE:"LEAF_interception_CLM5"       : interception and drainage of precipitation schemes modified from CLM5
   !* :SUBROUTINE:"LEAF_interception_NOAHMP"     : interception and drainage of precipitation schemes modified from Noah-MP
   !* :SUBROUTINE:"LEAF_interception_MATSIRO"    : interception and drainage of precipitation schemes modified from MATSIRO 2021 version
   !* :SUBROUTINE:"LEAF_interception_VIC"        : interception and drainage of precipitation schemes modified from VIC
   !* :SUBROUTINE:"LEAF_interception_JULES"      : interception and drainage of precipitation schemes modified from JULES
   !* :SUBROUTINE:"LEAF_interception_pftwrap"    : wapper for pft land use classification

!REVISION HISTORY:
!----------------
   ! 2024.04     Hua Yuan: add option to account for vegetation snow process based on Niu et al., 2004
   ! 2023.07     Hua Yuan: remove wrapper PC by using PFT leaf interception
   ! 2023.06     Shupeng Zhang @ SYSU
   ! 2023.02.23  Zhongwang Wei @ SYSU
   ! 2021.12.12  Zhongwang Wei @ SYSU
   ! 2020.10.21  Zhongwang Wei @ SYSU
   ! 2019.06     Hua Yuan: 1) add wrapper for PFT and PC, and 2) remove sigf by using lai+sai
   ! 2014.04     Yongjiu Dai
   ! 2002.08.31  Yongjiu Dai
   USE cudafor
   USE MOD_ConstVars_CUDA

   USE MOD_Precision

   IMPLICIT NONE

   real(r8), parameter ::  CICE        = 2.094E06  !specific heat capacity of ice (j/m3/k)
   real(r8), parameter ::  bp          = 20.
   real(r8), parameter ::  CWAT        = 4.188E06  !specific heat capacity of water (j/m3/k)
   real(r8), parameter ::  pcoefs(2,2) = reshape((/20.0_r8, 0.206e-8_r8, 0.0001_r8, 0.9999_r8/), (/2,2/))

CONTAINS

   attributes(device) SUBROUTINE LEAF_interception_CoLM2014 (deltim,dewmx,forc_us,forc_vs,chil,sigf,lai,sai,tair,tleaf,&
                                          prc_rain,prc_snow,prl_rain,prl_snow,bifall,&
                                          ldew,ldew_rain,ldew_snow,z0m,hu,pg_rain,pg_snow,qintr,qintr_rain,qintr_snow)
!DESCRIPTION
!===========
   ! Calculation of  interception and drainage of precipitation
   ! the treatment are based on Sellers et al. (1996)

!Original Author:
!-------------------
   !canopy interception scheme modified by Yongjiu Dai based on Sellers et al. (1996)

!References:
!-------------------
   !---Dai, Y., Zeng, X., Dickinson, R.E., Baker, I., Bonan, G.B., BosiloVICh, M.G., Denning, A.S.,
   !   Dirmeyer, P.A., Houser, P.R., Niu, G. and Oleson, K.w., 2003.
   !   The common land model. Bulletin of the American Meteorological Society, 84(8), pp.1013-1024.

   !---Lawrence, D.M., Thornton, P.E., Oleson, K.w. and Bonan, G.B., 2007.
   !   The partitioning of evapotranspiration into transpiration, soil evaporation,
   !   and canopy evaporation in a GCM: Impacts on land–atmosphere interaction. Journal of Hydrometeorology, 8(4), pp.862-880.

   !---Oleson, K., Dai, Y., Bonan, B., BosiloVIChm, M., Dickinson, R., Dirmeyer, P., Hoffman,
   !   F., Houser, P., Levis, S., Niu, G.Y. and Thornton, P., 2004.
   !   Technical description of the community land model (CLM).

   !---Sellers, P.J., Randall, D.A., Collatz, G.J., Berry, J.A., Field, C.B., Dazlich, D.A., Zhang, C.,
   !   Collelo, G.D. and Bounoua, L., 1996. A revised land surface parameterization (SiB2) for atmospheric GCMs.
   !   Part I: Model formulation. Journal of climate, 9(4), pp.676-705.

   !---Sellers, P.J., Tucker, C.J., Collatz, G.J., Los, S.O., Justice, C.O., Dazlich, D.A. and Randall, D.A., 1996.
   !   A revised land surface parameterization (SiB2) for atmospheric GCMs. Part II:
   !   The generation of global fields of terrestrial biophysical parameters from satellite data.
   !   Journal of climate, 9(4), pp.706-737.


!ANCILLARY FUNCTIONS AND SUBROUTINES
!-------------------

!REVISION HISTORY
!----------------
   !---2024.04.16  Hua Yuan: add option to account for vegetation snow process based on Niu et al., 2004
   !---2023.02.21  Zhongwang Wei @ SYSU : Snow and rain interception
   !---2021.12.08  Zhongwang Wei @ SYSU
   !---2019.06     Hua Yuan: remove sigf and USE lai+sai for judgement.
   !---2014.04     Yongjiu Dai
   !---2002.08.31  Yongjiu Dai
!=======================================================================

   IMPLICIT NONE

   real(r8), intent(in) :: deltim       !seconds in a time step [second]
   real(r8), intent(in) :: dewmx        !maximum dew [mm]
   real(r8), intent(in) :: forc_us      !wind speed
   real(r8), intent(in) :: forc_vs      !wind speed
   real(r8), intent(in) :: chil         !leaf angle distribution factor
   real(r8), intent(in) :: prc_rain     !convective ranfall [mm/s]
   real(r8), intent(in) :: prc_snow     !convective snowfall [mm/s]
   real(r8), intent(in) :: prl_rain     !large-scale rainfall [mm/s]
   real(r8), intent(in) :: prl_snow     !large-scale snowfall [mm/s]
   real(r8), intent(in) :: bifall       !bulk density of newly fallen dry snow [kg/m3]
   real(r8), intent(in) :: sigf         !fraction of veg cover, excluding snow-covered veg [-]
   real(r8), intent(in) :: lai          !leaf area index [-]
   real(r8), intent(in) :: sai          !stem area index [-]
   real(r8), intent(in) :: tair         !air temperature [K]
   real(r8), intent(in) :: tleaf        !sunlit canopy leaf temperature [K]

   real(r8), intent(inout) :: ldew      !depth of water on foliage [mm]
   real(r8), intent(inout) :: ldew_rain !depth of water on foliage [mm]
   real(r8), intent(inout) :: ldew_snow !depth of water on foliage [mm]
   real(r8), intent(in)    :: z0m       !roughness length
   real(r8), intent(in)    :: hu        !forcing height of U

   real(r8), intent(out) :: pg_rain     !rainfall onto ground including canopy runoff [kg/(m2 s)]
   real(r8), intent(out) :: pg_snow     !snowfall onto ground including canopy runoff [kg/(m2 s)]
   real(r8), intent(out) :: qintr       !interception [kg/(m2 s)]
   real(r8), intent(out) :: qintr_rain  !rainfall interception (mm h2o/s)
   real(r8), intent(out) :: qintr_snow  !snowfall interception (mm h2o/s)

   !----------------------- Dummy argument --------------------------------
   real(r8) :: satcap                     ! maximum allowed water on canopy [mm]
   real(r8) :: satcap_rain                ! maximum allowed rain on canopy [mm]
   real(r8) :: satcap_snow                ! maximum allowed snow on canopy [mm]
   real(r8) :: lsai                       ! sum of leaf area index and stem area index [-]
   real(r8) :: chiv                       ! leaf angle distribution factor
   real(r8) :: ppc                        ! convective precipitation in time-step [mm]
   real(r8) :: ppl                        ! large-scale precipitation in time-step [mm]
   real(r8) :: p0                         ! precipitation in time-step [mm]
   real(r8) :: fpi                        ! coefficient of interception
   real(r8) :: fpi_rain                   ! coefficient of interception of rain
   real(r8) :: fpi_snow                   ! coefficient of interception of snow
   real(r8) :: alpha_rain                 ! coefficient of interception of rain
   real(r8) :: alpha_snow                 ! coefficient of interception of snow
   real(r8) :: pinf                       ! interception of precipitation in time step [mm]
   real(r8) :: tti_rain                   ! direct rain throughfall in time step [mm]
   real(r8) :: tti_snow                   ! direct snow throughfall in time step [mm]
   real(r8) :: tex_rain                   ! canopy rain drainage in time step [mm]
   real(r8) :: tex_snow                   ! canopy snow drainage in time step [mm]
   real(r8) :: vegt                       ! sigf*lsai
   real(r8) :: xs                         ! proportion of the grid area where the intercepted rainfall
                                          ! plus the preexisting canopy water storage
   real(r8)  :: unl_snow_temp,U10,unl_snow_wind,unl_snow
   real(r8)  :: ap, cp, aa1, bb1, exrain, arg, w
   real(r8)  :: thru_rain, thru_snow
   real(r8)  :: xsc_rain, xsc_snow

   real(r8)  :: fvegc                     ! vegetation fraction
   real(r8)  :: FT                        ! the temperature factor for snow unloading
   real(r8)  :: FV                        ! the wind factor for snow unloading
   real(r8)  :: ICEDRIP                   ! snow unloading

   real(r8)  :: ldew_smelt
   real(r8)  :: ldew_frzc
   real(r8)  :: FP
   real(r8)  :: int_rain
   real(r8)  :: int_snow

   real(r8) :: qflx_irrig_drip
   real(r8) :: qflx_irrig_sprinkler
   real(r8) :: qflx_irrig_flood
   real(r8) :: qflx_irrig_paddy

      qflx_irrig_sprinkler = 0._r8

      IF (lai+sai > 1e-6) THEN
         lsai   = lai + sai
         vegt   = lsai
         satcap = dewmx*vegt
         satcap_rain = satcap
         satcap_snow = 6.6*(0.27+46./bifall)*vegt  ! Niu et al., 2004
         satcap_snow = 48.*satcap                  ! Simple one without snow density input

         p0  = (prc_rain + prc_snow + prl_rain + prl_snow + qflx_irrig_sprinkler)*deltim
         ppc = (prc_rain + prc_snow)*deltim
         ppl = (prl_rain + prl_snow + qflx_irrig_sprinkler)*deltim

         w = ldew+p0
         IF (tleaf > tfrz) THEN
            xsc_rain = max(0., ldew-satcap)
            xsc_snow = 0.
         ELSE
            xsc_rain = 0.
            xsc_snow = max(0., ldew-satcap)
         ENDIF

         ldew = ldew - (xsc_rain + xsc_snow)

         !TODO-done: account for vegetation snow
         IF ( d_DEF_VEG_SNOW ) THEN
            xsc_rain  = max(0., ldew_rain-satcap_rain)
            xsc_snow  = max(0., ldew_snow-satcap_snow)
            ldew_rain = ldew_rain - xsc_rain
            ldew_snow = ldew_snow - xsc_snow
            ldew      = ldew_rain + ldew_snow
         ENDIF

         ap = pcoefs(2,1)
         cp = pcoefs(2,2)

         IF (p0 > 1.e-8) THEN
            ap = ppc/p0 * pcoefs(1,1) + ppl/p0 * pcoefs(2,1)
            cp = ppc/p0 * pcoefs(1,2) + ppl/p0 * pcoefs(2,2)

            !----------------------------------------------------------------------
            !      proportional saturated area (xs) and leaf drainage(tex)
            !-----------------------------------------------------------------------
            chiv = chil
            IF ( abs(chiv) .le. 0.01 ) chiv = 0.01
            aa1 = 0.5 - 0.633 * chiv - 0.33 * chiv * chiv
            bb1 = 0.877 * ( 1. - 2. * aa1 )
            exrain = aa1 + bb1

            ! coefficient of interception
            ! set fraction of potential interception to max 0.25 (Lawrence et al. 2007)
            ! assume alpha_rain = alpha_snow
            alpha_rain = 0.25
            fpi = alpha_rain * ( 1.-exp(-exrain*lsai) )
            tti_rain = (prc_rain+prl_rain+qflx_irrig_sprinkler)*deltim * ( 1.-fpi )
            tti_snow = (prc_snow+prl_snow)*deltim * ( 1.-fpi )

            xs = 1.
            IF (p0*fpi>1.e-9) THEN
               arg = (satcap-ldew)/(p0*fpi*ap) - cp/ap
               IF (arg>1.e-9) THEN
                  xs = -1./bp * log( arg )
                  xs = min( xs, 1. )
                  xs = max( xs, 0. )
               ENDIF
            ENDIF

            ! assume no fall down of the intercepted snowfall in a time step
            ! drainage
            tex_rain = (prc_rain+prl_rain+qflx_irrig_sprinkler)*deltim * fpi * (ap/bp*(1.-exp(-bp*xs))+cp*xs) &
                     - (satcap-ldew) * xs
            tex_rain = max( tex_rain, 0. )
            tex_snow = 0.

            ! 04/11/2024, yuan:
            !TODO-done: account for snow on vegetation,
            IF ( d_DEF_VEG_SNOW ) THEN

               ! re-calculate leaf rain drainage using ldew_rain

               xs = 1.
               IF (p0*fpi>1.e-9) THEN
                  arg = (satcap_rain-ldew_rain)/(p0*fpi*ap) - cp/ap
                  IF (arg>1.e-9) THEN
                     xs = -1./bp * log( arg )
                     xs = min( xs, 1. )
                     xs = max( xs, 0. )
                  ENDIF
               ENDIF

               tex_rain = (prc_rain+prl_rain+qflx_irrig_sprinkler)*deltim * fpi * (ap/bp*(1.-exp(-bp*xs))+cp*xs) &
                        - (satcap_rain-ldew_rain) * xs
               tex_rain = max( tex_rain, 0. )

               ! re-calculate the snow loading rate

               fvegc = 1. - exp(-0.52*lsai)
               FP    = (ppc + ppl) / (10.*ppc + ppl)
               qintr_snow = fvegc * (prc_snow+prl_snow) * FP
               qintr_snow = min (qintr_snow, (satcap_snow-ldew_snow)/deltim * (1.-exp(-(prc_snow+prl_snow)*deltim/satcap_snow)) )
               qintr_snow = max (qintr_snow, 0.)

               ! snow unloading rate

               FT = max(0.0, (tleaf - tfrz) / 1.87e5)
               FV = sqrt(forc_us*forc_us + forc_vs*forc_vs) / 1.56e5
               tex_snow = max(0., ldew_snow/deltim) * (FV+FT)
               tti_snow = (1.0-fvegc)*(prc_snow+prl_snow) + (fvegc*(prc_snow+prl_snow) - qintr_snow)

               ! rate -> mass

               tti_snow = tti_snow * deltim
               tex_snow = tex_snow * deltim
            ENDIF

#if(defined CoLMDEBUG)
            IF (tex_rain+tex_snow+tti_rain+tti_snow-p0 > 1.e-10) THEN
               write(6,*) 'tex_ + tti_ > p0 in interception code : '
            ENDIF
#endif

         ELSE
            ! all intercepted by canopy leves for very small precipitation
            tti_rain = 0.
            tti_snow = 0.
            tex_rain = 0.
            tex_snow = 0.
         ENDIF

         !----------------------------------------------------------------------
         !   total throughfall (thru) and store augmentation
         !----------------------------------------------------------------------

         thru_rain = tti_rain + tex_rain
         thru_snow = tti_snow + tex_snow
         pinf = p0 - (thru_rain + thru_snow)
         ldew = ldew + pinf

         !TODO-done: IF d_DEF_VEG_SNOW, update ldew_rain, ldew_snow
         IF ( d_DEF_VEG_SNOW ) THEN
            ldew_rain = ldew_rain + (prc_rain+prl_rain+qflx_irrig_sprinkler)*deltim - thru_rain
            ldew_snow = ldew_snow + (prc_snow+prl_snow)*deltim - thru_snow
            ldew = ldew_rain + ldew_snow
         ENDIF

         pg_rain = (xsc_rain + thru_rain) / deltim
         pg_snow = (xsc_snow + thru_snow) / deltim
         qintr   = pinf / deltim

         qintr_rain = prc_rain + prl_rain + qflx_irrig_sprinkler - thru_rain / deltim
         qintr_snow = prc_snow + prl_snow - thru_snow / deltim

#if(defined CoLMDEBUG)
         w = w - ldew - (pg_rain+pg_snow)*deltim
         IF (abs(w) > 1.e-6) THEN
            write(6,*) 'something wrong in interception code : '
            write(6,*) w, ldew, (pg_rain+pg_snow)*deltim, satcap
            stop
         ENDIF

         IF (d_DEF_VEG_SNOW .and. abs(ldew-ldew_rain-ldew_snow) > 1.e-6) THEN
            write(6,*) 'something wrong in interception code when d_DEF_VEG_SNOW : '
            write(6,*) ldew, ldew_rain, ldew_snow
            stop
         ENDIF
#endif

      ELSE
         ! 07/15/2023, yuan: #bug found for ldew value reset.
         !NOTE: this bug should exist in other interception schemes @Zhongwang.
         IF (ldew > 0.) THEN
            IF (tleaf > tfrz) THEN
               pg_rain = prc_rain + prl_rain + qflx_irrig_sprinkler + ldew/deltim
               pg_snow = prc_snow + prl_snow
            ELSE
               pg_rain = prc_rain + prl_rain + qflx_irrig_sprinkler
               pg_snow = prc_snow + prl_snow + ldew/deltim
            ENDIF
         ELSE
            pg_rain = prc_rain + prl_rain + qflx_irrig_sprinkler
            pg_snow = prc_snow + prl_snow
         ENDIF

         ldew       = 0.
         ldew_rain  = 0.
         ldew_snow  = 0.
         qintr      = 0.
         qintr_rain = 0.
         qintr_snow = 0.

      ENDIF

   END SUBROUTINE LEAF_interception_CoLM2014

   attributes(device) SUBROUTINE LEAF_interception_wrap(deltim,dewmx,forc_us,forc_vs,chil,sigf,lai,sai,tair,tleaf, &
                                                    prc_rain,prc_snow,prl_rain,prl_snow,bifall, &
                                                       ldew,ldew_rain,ldew_snow,z0m,hu,pg_rain, &
                                                            pg_snow,qintr,qintr_rain,qintr_snow)
!DESCRIPTION
!===========
   !wrapper for calculation of canopy interception using USGS or IGBP land cover classification

!ANCILLARY FUNCTIONS AND SUBROUTINES
!-------------------

!Original Author:
!-------------------
   !---Shupeng Zhang

!References:


!REVISION HISTORY
!----------------

   IMPLICIT NONE

   real(r8), intent(in)    :: deltim     !seconds in a time step [second]
   real(r8), intent(in)    :: dewmx      !maximum dew [mm]
   real(r8), intent(in)    :: forc_us    !wind speed
   real(r8), intent(in)    :: forc_vs    !wind speed
   real(r8), intent(in)    :: chil       !leaf angle distribution factor
   real(r8), intent(in)    :: prc_rain   !convective ranfall [mm/s]
   real(r8), intent(in)    :: prc_snow   !convective snowfall [mm/s]
   real(r8), intent(in)    :: prl_rain   !large-scale rainfall [mm/s]
   real(r8), intent(in)    :: prl_snow   !large-scale snowfall [mm/s]
   real(r8), intent(in)    :: bifall     !bulk density of newly fallen dry snow [kg/m3]
   real(r8), intent(in)    :: sigf       !fraction of veg cover, excluding snow-covered veg [-]
   real(r8), intent(in)    :: lai        !leaf area index [-]
   real(r8), intent(in)    :: sai        !stem area index [-]
   real(r8), intent(in)    :: tair       !air temperature [K]
   real(r8), intent(inout) :: tleaf      !sunlit canopy leaf temperature [K]

   real(r8), intent(inout) :: ldew       !depth of water on foliage [mm]
   real(r8), intent(inout) :: ldew_rain  !depth of liquid on foliage [mm]
   real(r8), intent(inout) :: ldew_snow  !depth of liquid on foliage [mm]
   real(r8), intent(in)    :: z0m        !roughness length
   real(r8), intent(in)    :: hu         !forcing height of U


   real(r8), intent(out)   :: pg_rain    !rainfall onto ground including canopy runoff [kg/(m2 s)]
   real(r8), intent(out)   :: pg_snow    !snowfall onto ground including canopy runoff [kg/(m2 s)]
   real(r8), intent(out)   :: qintr      !interception [kg/(m2 s)]
   real(r8), intent(out)   :: qintr_rain !rainfall interception (mm h2o/s)
   real(r8), intent(out)   :: qintr_snow !snowfall interception (mm h2o/s)

      IF (d_DEF_Interception_scheme==1) THEN
         CALL LEAF_interception_CoLM2014 (deltim,dewmx,forc_us,forc_vs,chil,sigf,lai,sai,tair,tleaf,&
                                             prc_rain,prc_snow,prl_rain,prl_snow,bifall,&
                                             ldew,ldew_rain,ldew_snow,z0m,hu,pg_rain,&
                                             pg_snow,qintr,qintr_rain,qintr_snow)
      ELSE
         print *, "[Zeating] Only Supported LEAF_interception_CoLM2014 with d_DEF_Interception_scheme 1 !!"
         print *, "[Zeating] d_DEF_Interception_scheme = ", d_DEF_Interception_scheme
      ENDIF

   END SUBROUTINE LEAF_interception_wrap

END MODULE MOD_LeafInterception_CUDA
