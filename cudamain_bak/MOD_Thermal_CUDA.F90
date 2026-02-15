#include <define.h>

MODULE MOD_Thermal_CUDA

!-----------------------------------------------------------------------
   USE cudafor
   USE MOD_ConstVars_CUDA

   USE MOD_Precision
   IMPLICIT NONE
   SAVE

! PUBLIC MEMBER FUNCTIONS:
   PUBLIC :: THERMAL


!-----------------------------------------------------------------------

CONTAINS

!-----------------------------------------------------------------------


   attributes(device) SUBROUTINE THERMAL (ipatch ,patchtype,is_dry_lake,lb            ,deltim        ,&
                       trsmx0        ,zlnd          ,zsno          ,csoilc        ,&
                       dewmx         ,capr          ,cnfac         ,vf_quartz     ,&
                       vf_gravels    ,vf_om         ,vf_sand       ,wf_gravels    ,&
                       wf_sand       ,csol          ,porsl         ,psi0          ,&
#ifdef Campbell_SOIL_MODEL
                       bsw           ,&
#endif
#ifdef vanGenuchten_Mualem_SOIL_MODEL
                       theta_r       ,alpha_vgm     ,n_vgm         ,L_vgm         ,&
                       sc_vgm        ,fc_vgm        ,                              &
#endif
                       k_solids      ,dksatu        ,dksatf        ,dkdry         ,&
                       BA_alpha      ,BA_beta       ,lai           ,laisun        ,&
                       laisha        ,sai           ,htop          ,hbot          ,&
                       t_sqrtdi        ,t_rootfr        ,rstfacsun_out ,rstfacsha_out ,&
                       rss           ,gssun_out     ,gssha_out     ,assimsun_out  ,&
                       etrsun_out    ,assimsha_out  ,etrsha_out    ,&
!photosynthesis and plant hydraulic variables
                       t_effcon        ,t_vmax25        ,hksati        ,smp     ,hk   ,&
                       t_kmax_sun      ,t_kmax_sha      ,t_kmax_xyl      ,t_kmax_root     ,&
                       t_psi50_sun     ,t_psi50_sha     ,t_psi50_xyl     ,t_psi50_root    ,&
                       t_ck            ,vegwp         ,gs0sun        ,gs0sha        ,&
!Ozone stress variables
                       lai_old       ,o3uptakesun   ,o3uptakesha   ,forc_ozone    ,&
!end ozone stress variables
!Ozone WUE stomata model parameter
                       t_lambda        ,&! Marginal water cost of carbon gain ((mol h2o) (mol co2)-1)
!End WUE stomata model parameter
                       t_slti          ,t_hlti          ,t_shti          ,t_hhti          ,&
                       t_trda          ,t_trdm          ,t_trop          ,t_g1            ,&
                       t_g0            ,t_gradm         ,t_binter        ,t_extkn         ,&
                       forc_hgt_u    ,forc_hgt_t    ,forc_hgt_q    ,forc_us       ,&
                       forc_vs       ,forc_t        ,forc_q        ,forc_rhoair   ,&
                       forc_psrf     ,forc_pco2m    ,forc_hpbl     ,forc_po2m     ,&
                       coszen        ,parsun        ,parsha        ,sabvsun       ,&
                       sabvsha       ,sabg          ,sabg_soil     ,sabg_snow     ,&
                       frl           ,extkb         ,extkd         ,thermk        ,&
                       fsno          ,sigf          ,dz_soisno     ,z_soisno      ,&
                       zi_soisno     ,tleaf         ,t_soisno      ,wice_soisno   ,&
                       wliq_soisno   ,ldew          ,ldew_rain     ,ldew_snow     ,&
                       fwet_snow     ,scv           ,snowdp        ,imelt         ,&
                       taux          ,tauy          ,fsena         ,fevpa         ,&
                       lfevpa        ,fsenl         ,fevpl         ,etr           ,&
                       fseng         ,fevpg         ,olrg          ,fgrnd         ,&
                       rootr         ,rootflux      ,qseva         ,qsdew         ,&
                       qsubl         ,qfros         ,qseva_soil    ,qsdew_soil    ,&
                       qsubl_soil    ,qfros_soil    ,qseva_snow    ,qsdew_snow    ,&
                       qsubl_snow    ,qfros_snow    ,sm            ,tref          ,&
                       qref          ,trad          ,rst           ,assim         ,&
                       respc         ,errore        ,emis          ,z0m           ,&
                       zol           ,rib           ,ustar         ,qstar         ,&
                       tstar         ,fm            ,fh            ,fq            ,&
                       pg_rain       ,pg_snow       ,t_precip      ,qintr_rain    ,&
                       qintr_snow    ,snofrz        ,sabg_snow_lyr                ,&
                        amx_hr,bmx_hr,cmx_hr,rmx_hr,drmx_hr,hx,hdx,xroot,zmm,qeroot_nl)

!=======================================================================
!  this is the main subroutine to execute the calculation
!  of thermal processes and surface fluxes
!
!  Original author: Yongjiu Dai, 09/15/1999; 08/30/2002
!
!  FLOW DIAGRAM FOR THERMAL.F90
!
!  THERMAL ===> qsadv
!               GroundFluxes
!               eroot                             |dewfraction
!               LeafTemperature   |               |qsadv
!               LeafTemperaturePC |  ---------->  |moninobukini
!                                                 |moninobuk
!                                                 |MOD_AssimStomataConductance
!
!               GroundTemperature    ---------->   meltf
!
!
! !REVISIONS:
!  08/2019, Hua Yuan: added initial codes for PFT and Plant Community
!           (PC) vegetation classification processes
!
!  01/2021, Nan Wei: added variables passing of plant hydraulics and
!           precipitation sensible heat with canopy and ground for PFT
!           and Plant Community (PC)
!=======================================================================

   USE MOD_Precision
   USE MOD_Eroot_CUDA
   USE MOD_GroundFluxes_CUDA
   USE MOD_LeafTemperature_CUDA
   USE MOD_GroundTemperature_CUDA
   USE MOD_Qsadv_CUDA
   USE MOD_SoilSurfaceResistance_CUDA
#ifdef vanGenuchten_Mualem_SOIL_MODEL
   USE MOD_Hydro_SoilFunction_CUDA, only: soil_psi_from_vliq
#endif
   USE MOD_SPMD_Task_CUDA

   IMPLICIT NONE

!-------------------------- Dummy Arguments ----------------------------

   integer, intent(in) :: &
       ipatch,                   &! patch index
       lb,                       &! lower bound of array
       patchtype                  ! land patch type (0=soil, 1=urban or built-up, 2=wetland,
                                  !                  3=glacier/ice sheet, 4=land water bodies)
   integer, intent(in) :: is_dry_lake

   real(r8), intent(inout) :: &
       sai                        ! stem area index  [-]
   real(r8), intent(in) :: &
       deltim,                   &! model time step [second]
       trsmx0,                   &! max transpiration for moist soil+100% veg.  [mm/s]
       zlnd,                     &! roughness length for soil [m]
       zsno,                     &! roughness length for snow [m]
       csoilc,                   &! drag coefficient for soil under canopy [-]
       dewmx,                    &! maximum dew
       capr,                     &! tuning factor to turn first layer T into surface T
       cnfac,                    &! Crank Nicholson factor between 0 and 1

       ! soil physical parameters
       vf_quartz (1:nl_soil),    &! volumetric fraction of quartz within mineral soil
       vf_gravels(1:nl_soil),    &! volumetric fraction of gravels
       vf_om     (1:nl_soil),    &! volumetric fraction of organic matter
       vf_sand   (1:nl_soil),    &! volumetric fraction of sand
       wf_gravels(1:nl_soil),    &! gravimetric fraction of gravels
       wf_sand   (1:nl_soil),    &! gravimetric fraction of sand
       csol      (1:nl_soil),    &! heat capacity of soil solids [J/(m3 K)]
       porsl     (1:nl_soil),    &! soil porosity [-]
       psi0      (1:nl_soil),    &! soil water suction, negative potential [mm]
#ifdef Campbell_SOIL_MODEL
       bsw(1:nl_soil),           &! clapp and hornberger "b" parameter [-]
#endif
       k_solids  (1:nl_soil),    &! thermal conductivity of minerals soil [W/m-K]
       dkdry     (1:nl_soil),    &! thermal conductivity of dry soil [W/m-K]
       dksatu    (1:nl_soil),    &! thermal conductivity of saturated unfrozen soil [W/m-K]
       dksatf    (1:nl_soil),    &! thermal conductivity of saturated frozen soil [W/m-K]
       hksati    (1:nl_soil),    &! hydraulic conductivity at saturation [mm h2o/s]
       BA_alpha  (1:nl_soil),    &! alpha in Balland and Arp(2005) thermal conductivity scheme
       BA_beta   (1:nl_soil),    &! beta in Balland and Arp(2005) thermal conductivity scheme

       ! vegetation parameters
       lai,                      &! adjusted leaf area index for seasonal variation [-]
       htop,                     &! canopy crown top height [m]
       hbot,                     &! canopy crown bottom height [m]
       t_sqrtdi,                   &! inverse sqrt of leaf dimension [m**-0.5]
       t_rootfr(1:nl_soil),        &! root fraction

       t_effcon,                   &! quantum efficiency of RuBP regeneration (mol CO2/mol quanta)
       t_vmax25,                   &! maximum carboxylation rate at 25 C at canopy top
       t_kmax_sun,                 &! Plant Hydraulics Parameters
       t_kmax_sha,                 &! Plant Hydraulics Parameters
       t_kmax_xyl,                 &! Plant Hydraulics Parameters
       t_kmax_root,                &! Plant Hydraulics Parameters
       t_psi50_sun,                &! water potential at 50% loss of sunlit leaf tissue conductance (mmH2O)
       t_psi50_sha,                &! water potential at 50% loss of shaded leaf tissue conductance (mmH2O)
       t_psi50_xyl,                &! water potential at 50% loss of xylem tissue conductance (mmH2O)
       t_psi50_root,               &! water potential at 50% loss of root tissue conductance (mmH2O)
       t_ck,                       &! shape-fitting parameter for vulnerability curve (-)
       t_slti,                     &! slope of low temperature inhibition function      [s3]
       t_hlti,                     &! 1/2 point of low temperature inhibition function  [s4]
       t_shti,                     &! slope of high temperature inhibition function     [s1]
       t_hhti,                     &! 1/2 point of high temperature inhibition function [s2]
       t_trda,                     &! temperature coefficient in gs-a model             [s5]
       t_trdm,                     &! temperature coefficient in gs-a model             [s6]
       t_trop,                     &! temperature coefficient in gs-a model
       t_g1,                       &! conductance-photosynthesis slope parameter for medlyn model
       t_g0,                       &! conductance-photosynthesis intercept for medlyn model
       t_gradm,                    &! conductance-photosynthesis slope parameter
       t_binter,                   &! conductance-photosynthesis intercept
       t_extkn,                    &! coefficient of leaf nitrogen allocation

       ! atmospherical variables and observational height
       forc_hgt_u,               &! observational height of wind [m]
       forc_hgt_t,               &! observational height of temperature [m]
       forc_hgt_q,               &! observational height of humidity [m]
       forc_us,                  &! wind component in eastward direction [m/s]
       forc_vs,                  &! wind component in northward direction [m/s]
       forc_t,                   &! temperature at agcm reference height [kelvin]
       forc_q,                   &! specific humidity at agcm reference height [kg/kg]
       forc_rhoair,              &! density air [kg/m3]
       forc_psrf,                &! atmosphere pressure at the surface [pa]
       forc_pco2m,               &! CO2 concentration in atmos. (pascals)
       forc_po2m,                &! O2 concentration in atmos. (pascals)
       forc_hpbl,                &! atmospheric boundary layer height [m]
       pg_rain,                  &! rainfall onto ground including canopy runoff [kg/(m2 s)]
       pg_snow,                  &! snowfall onto ground including canopy runoff [kg/(m2 s)]
       t_precip,                 &! snowfall/rainfall temperature [kelvin]
       qintr_rain,               &! rainfall interception (mm h2o/s)
       qintr_snow,               &! snowfall interception (mm h2o/s)

       ! radiative fluxes
       coszen,                   &! cosine of the solar zenith angle
       parsun,                   &! photosynthetic active radiation by sunlit leaves (W m-2)
       parsha,                   &! photosynthetic active radiation by shaded leaves (W m-2)
       sabvsun,                  &! solar radiation absorbed by vegetation [W/m2]
       sabvsha,                  &! solar radiation absorbed by vegetation [W/m2]
       sabg,                     &! solar radiation absorbed by ground [W/m2]
       sabg_soil,                &! solar radiation absorbed by ground soil [W/m2]
       sabg_snow,                &! solar radiation absorbed by ground snow [W/m2]
       frl,                      &! atmospheric infrared (longwave) radiation [W/m2]
       extkb,                    &! (k, g(mu)/mu) direct solar extinction coefficient
       extkd,                    &! diffuse and scattered diffuse PAR extinction coefficient
       thermk,                   &! canopy gap fraction for tir radiation

       ! state variable (1)
       fsno,                     &! fraction of ground covered by snow
       sigf,                     &! fraction of veg cover, excluding snow-covered veg [-]
       dz_soisno(lb:nl_soil),    &! layer thickness [m]
       z_soisno (lb:nl_soil),    &! node depth [m]
       zi_soisno(lb-1:nl_soil)    ! interface depth [m]

   real(r8), intent(in) :: &
       sabg_snow_lyr(lb:1)        ! snow layer absorption

       ! state variables (2)
   real(r8), intent(inout) :: &
       vegwp(1:nvegwcs),         &! vegetation water potential
       gs0sun,                   &! working copy of sunlit stomata conductance
       gs0sha,                   &! working copy of shaded stomata conductance
!Ozone stress variables
       lai_old    ,              &! lai in last time step
       o3uptakesun,              &! Ozone does, sunlit leaf (mmol O3/m^2)
       o3uptakesha,              &! Ozone does, shaded leaf (mmol O3/m^2)
       forc_ozone ,              &! Ozone
!end ozone stress variables

!Ozone WUE stomata model parameter
       t_lambda,                   &! Marginal water cost of carbon gain ((mol h2o) (mol co2)-1)
!End WUE stomata model parameter

       tleaf,                    &! shaded leaf temperature [K]
       t_soisno(lb:nl_soil),     &! soil temperature [K]
       wice_soisno(lb:nl_soil),  &! ice lens [kg/m2]
       wliq_soisno(lb:nl_soil)    ! liquid water [kg/m2]

   real(r8), intent(in) :: &
       smp(1:nl_soil)         ,  &! soil matrix potential [mm]
       hk(1:nl_soil)              ! hydraulic conductivity [mm h2o/s]

   real(r8), intent(inout) :: &
       ldew,                     &! depth of water on foliage [kg/(m2 s)]
       ldew_rain,                &! depth of rain on foliage [kg/(m2 s)]
       ldew_snow,                &! depth of rain on foliage [kg/(m2 s)]
       fwet_snow,                &! vegetation canopy snow fractional cover [-]
       scv,                      &! snow cover, water equivalent [mm, kg/m2]
       snowdp                     ! snow depth [m]

   real(r8), intent(out) :: &
       snofrz (lb:0)              !snow freezing rate (col,lyr) [kg m-2 s-1]

   integer,  intent(out) :: &
       imelt(lb:nl_soil)          ! flag for melting or freezing [-]

   real(r8), intent(out) :: &
       laisun,                   &! sunlit leaf area index
       laisha,                   &! shaded leaf area index
       gssun_out,                &! sunlit stomata conductance
       gssha_out,                &! shaded stomata conductance
       rstfacsun_out,            &! factor of soil water stress on sunlit leaf
       rstfacsha_out              ! factor of soil water stress on shaded leaf

   real(r8), intent(out) :: &
       assimsun_out ,            &! diagnostic sunlit leaf assim value for output
       etrsun_out   ,            &! diagnostic sunlit leaf etr value for output
       assimsha_out ,            &! diagnostic shaded leaf assim for output
       etrsha_out                 ! diagnostic shaded leaf etr for output

       ! Output fluxes
   real(r8), intent(out) :: &
       taux,                     &! wind stress: E-W [kg/m/s**2]
       tauy,                     &! wind stress: N-S [kg/m/s**2]
       fsena,                    &! sensible heat from canopy height to atmosphere [W/m2]
       fevpa,                    &! evapotranspiration from canopy height to atmosphere [mm/s]
       lfevpa,                   &! latent heat flux from canopy height to atmosphere [W/m2]
       fsenl,                    &! sensible heat from leaves [W/m2]
       fevpl,                    &! evaporation+transpiration from leaves [mm/s]
       etr,                      &! transpiration rate [mm/s]
       fseng,                    &! sensible heat flux from ground [W/m2]
       fevpg,                    &! evaporation heat flux from ground [mm/s]
       olrg,                     &! outgoing long-wave radiation from ground+canopy
       fgrnd,                    &! ground heat flux [W/m2]
       rootr(1:nl_soil),         &! water uptake fraction from different layers, all layers add to 1.0
       rootflux(1:nl_soil),      &! root uptake from different layer, all layers add to transpiration

       qseva,                    &! ground surface evaporation rate (mm h2o/s)
       qsdew,                    &! ground surface dew formation (mm h2o /s) [+]
       qsubl,                    &! sublimation rate from snow pack (mm h2o /s) [+]
       qfros,                    &! surface dew added to snow pack (mm h2o /s) [+]
       qseva_soil,               &! ground soil surface evaporation rate (mm h2o/s)
       qsdew_soil,               &! ground soil surface dew formation (mm h2o /s) [+]
       qsubl_soil,               &! sublimation rate from soil ice pack (mm h2o /s) [+]
       qfros_soil,               &! surface dew added to soil ice pack (mm h2o /s) [+]
       qseva_snow,               &! ground snow surface evaporation rate (mm h2o/s)
       qsdew_snow,               &! ground snow surface dew formation (mm h2o /s) [+]
       qsubl_snow,               &! sublimation rate from snow pack (mm h2o /s) [+]
       qfros_snow,               &! surface dew added to snow pack (mm h2o /s) [+]

       sm,                       &! rate of snowmelt [kg/(m2 s)]
       tref,                     &! 2 m height air temperature [kelvin]
       qref,                     &! 2 m height air specific humidity
       trad,                     &! radiative temperature [K]
       rss,                      &! bare soil resistance for evaporation [s/m]
       rst,                      &! stomatal resistance (s m-1)
       assim,                    &! assimilation
       respc,                    &! respiration

       ! additional variables required by coupling with WRF or RSM model
       emis,                     &! averaged bulk surface emissivity
       z0m,                      &! effective roughness [m]
       zol,                      &! dimensionless height (z/L) used in Monin-Obukhov theory
       rib,                      &! bulk Richardson number in surface layer
       ustar,                    &! u* in similarity theory [m/s]
       qstar,                    &! q* in similarity theory [kg/kg]
       tstar,                    &! t* in similarity theory [K]
       fm,                       &! integral of profile function for momentum
       fh,                       &! integral of profile function for heat
       fq                         ! integral of profile function for moisture

   real(r8), intent(inout) :: amx_hr(nl_soil)  ! "a" left off diagonal of tridiagonal matrix
   real(r8), intent(inout) :: bmx_hr(nl_soil)  ! "b" diagonal column for tridiagonal matrix
   real(r8), intent(inout) :: cmx_hr(nl_soil)  ! "c" right off diagonal tridiagonal matrix
   real(r8), intent(inout) :: rmx_hr(nl_soil)  ! "r" forcing term of tridiagonal matrix
   real(r8), intent(inout) :: drmx_hr(nl_soil-1) ! "dr" forcing term of tridiagonal matrix for d/dxroot(1)
   real(r8), intent(inout) :: hx(nl_soil)       ! root water potential from layer 2 to nl_soil
   real(r8), intent(inout) :: hdx(nl_soil-1)      ! derivate of root water potential from layer 2 to nl_soil (dxroot(:)/dxroot(1))
   real(r8), intent(inout) :: xroot(nl_soil)     ! root water potential from layer 2 to nl_soil
   real(r8), intent(inout) :: zmm(1:nl_soil)     ! layer depth [mm]
   real(r8), intent(inout) :: qeroot_nl(1:nl_soil) ! root water potential from layer 2 to nl_soil
!-------------------------- Local Variables ----------------------------

   integer i,j

   real(r8) :: &
       fseng_soil,               &! sensible heat flux from soil fraction
       fseng_snow,               &! sensible heat flux from snow fraction
       fevpg_soil,               &! latent heat flux from soil fraction
       fevpg_snow,               &! latent heat flux from snow fraction

       cgrnd,                    &! deriv. of soil energy flux wrt to soil temp [w/m2/k]
       cgrndl,                   &! deriv, of soil sensible heat flux wrt soil temp [w/m2/k]
       cgrnds,                   &! deriv of soil latent heat flux wrt soil temp [w/m**2/k]
       degdT,                    &! d(eg)/dT
       dqgdT,                    &! d(qg)/dT
       dlrad,                    &! downward longwave radiation blow the canopy [W/m2]
       eg,                       &! water vapor pressure at temperature T [pa]
       egsmax,                   &! max. evaporation which soil can provide at one time step
       egidif,                   &! the excess of evaporation over "egsmax"
       emg,                      &! ground emissivity (0.97 for snow,
                                  ! glaciers and water surface; 0.96 for soil and wetland)
       errore,                   &! energy balnce error [w/m2]
       etrc,                     &! maximum possible transpiration rate [mm/s]
       fac,                      &! soil wetness of surface layer
       fact(lb:nl_soil),         &! used in computing tridiagonal matrix
       fsun,                     &! fraction of sunlit canopy
       hr,                       &! relative humidity
       htvp,                     &! latent heat of vapor of water (or sublimation) [j/kg]
       olru,                     &! olrg excluding dwonwelling reflection [W/m2]
       olrb,                     &! olrg assuming blackbody emission [W/m2]
       psit,                     &! negative potential of soil
       qg,                       &! ground specific humidity [kg/kg]
! 03/07/2020, yuan:
       q_soil,                   &! ground soil specific humidity [kg/kg]
       q_snow,                   &! ground snow specific humidity [kg/kg]
       qsatg,                    &! saturated humidity [kg/kg]
       qsatgdT,                  &! d(qsatg)/dT
       qred,                     &! soil surface relative humidity
       sabv,                     &! solar absorbed by canopy [W/m2]
       thm,                      &! intermediate variable (forc_t+0.0098*forc_hgt_t)
       th,                       &! potential temperature (kelvin)
       thv,                      &! virtual potential temperature (kelvin)
       rstfac,                   &! factor of soil water stress
       t_grnd,                   &! ground surface temperature [K]
       t_grnd_bef,               &! ground surface temperature [K]
       t_soil,                   &! ground soil temperature
       t_snow,                   &! ground snow temperature
       t_soisno_bef(lb:nl_soil), &! soil/snow temperature before update
       tinc,                     &! temperature difference of two time step
       ur,                       &! wind speed at reference height [m/s]
       ulrad,                    &! upward longwave radiation above the canopy [W/m2]
       wice0(lb:nl_soil),        &! ice mass from previous time-step
       wliq0(lb:nl_soil),        &! liquid mass from previous time-step
       wx,                       &! patial volume of ice and water of surface layer
       xmf,                      &! total latent heat of phase change of ground water [W/m2]
       hprl,                     &! precipitation sensible heat from canopy [W/m2]
       dheatl                     ! vegetation heat change [W/m2]

   real(r8) :: z0m_g,z0h_g,zol_g,obu_g,rib_g,ustar_g,qstar_g,tstar_g
   real(r8) :: fm10m,fm_g,fh_g,fq_g,fh2m,fq2m,um,obu
!Ozone stress variables
   real(r8) :: o3coefv_sun, o3coefv_sha, o3coefg_sun, o3coefg_sha
!end ozone stress variables

   integer p, ps, pe, pc

   real(r8), allocatable :: rootr_p     (:,:)
   real(r8), allocatable :: rootflux_p  (:,:)
   real(r8), allocatable :: etrc_p        (:)
   real(r8), allocatable :: rstfac_p      (:)
   real(r8), allocatable :: rstfacsun_p   (:)
   real(r8), allocatable :: rstfacsha_p   (:)
   real(r8), allocatable :: gssun_p       (:)
   real(r8), allocatable :: gssha_p       (:)
   real(r8), allocatable :: fsun_p        (:)
   real(r8), allocatable :: sabv_p        (:)

! 03/06/2020, yuan: added
   real(r8), allocatable :: fseng_soil_p  (:)
   real(r8), allocatable :: fseng_snow_p  (:)
   real(r8), allocatable :: fevpg_soil_p  (:)
   real(r8), allocatable :: fevpg_snow_p  (:)
   real(r8), allocatable :: cgrnd_p       (:)
   real(r8), allocatable :: cgrnds_p      (:)
   real(r8), allocatable :: cgrndl_p      (:)
   real(r8), allocatable :: dlrad_p       (:)
   real(r8), allocatable :: ulrad_p       (:)
   real(r8), allocatable :: zol_p         (:)
   real(r8), allocatable :: rib_p         (:)
   real(r8), allocatable :: ustar_p       (:)
   real(r8), allocatable :: qstar_p       (:)
   real(r8), allocatable :: tstar_p       (:)
   real(r8), allocatable :: fm_p          (:)
   real(r8), allocatable :: fh_p          (:)
   real(r8), allocatable :: fq_p          (:)
   real(r8), allocatable :: hprl_p        (:)
   real(r8), allocatable :: assimsun_p    (:)
   real(r8), allocatable :: etrsun_p      (:)
   real(r8), allocatable :: assimsha_p    (:)
   real(r8), allocatable :: etrsha_p      (:)
   real(r8), allocatable :: dheatl_p      (:)


!=======================================================================
! [1] Initial set and propositional variables
!=======================================================================

      ! emissivity
      emg = 0.96
      IF (scv>0. .or. patchtype==3) emg = 0.97

      ! fluxes
      taux   = 0.;  tauy   = 0.
      fsena  = 0.;  fevpa  = 0.
      lfevpa = 0.;  fsenl  = 0.
      fevpl  = 0.;  etr    = 0.
      fseng  = 0.;  fevpg  = 0.

      cgrnds = 0.;  cgrndl = 0.
      cgrnd  = 0.;  tref   = 0.
      qref   = 0.;  rst    = 2.0e4
      assim  = 0.;  respc  = 0.
      hprl   = 0.;  dheatl = 0.

      emis   = 0.;  z0m    = 0.
      zol    = 0.;  rib    = 0.
      ustar  = 0.;  qstar  = 0.
      tstar  = 0.;  rootr  = 0.
      rootflux = 0.

      dlrad  = frl

      t_soil = t_soisno(1)
      t_snow = t_soisno(lb)

IF (.not.d_DEF_SPLIT_SOILSNOW) THEN
      t_grnd = t_soisno(lb)
      ulrad  = frl*(1.-emg) + emg*stefnc*t_grnd**4
ELSE
      t_grnd = fsno*t_snow  + (1.-fsno)*t_soil
      ulrad  = frl*(1.-emg) &
             + fsno*emg*stefnc*t_snow**4 &
             + (1.-fsno)*emg*stefnc*t_soil**4
ENDIF

      ! temperature and water mass from previous time step
      t_soisno_bef(lb:) = t_soisno(lb:)
      t_grnd_bef = t_grnd
      wice0(lb:) = wice_soisno(lb:)
      wliq0(lb:) = wliq_soisno(lb:)

      ! latent heat, assumed that the sublimation occurred only as wliq_soisno=0
      htvp = hvap
      IF (wliq_soisno(lb)<=0. .and. wice_soisno(lb)>0.) htvp = hsub

      ! potential temperature at the reference height
      thm = forc_t + 0.0098*forc_hgt_t                     !intermediate variable equivalent to
                                                           !forc_t*(pgcm/forc_psrf)**(rgas/cpair)
      th  = forc_t*(100000./forc_psrf)**(rgas/cpair)       !potential T
      thv = th*(1.+0.61*forc_q)                            !virtual potential T
      ur  = max(0.1,sqrt(forc_us*forc_us+forc_vs*forc_vs)) !limit set to 0.1


!=======================================================================
! [2] specific humidity and its derivative at ground surface
!=======================================================================

      qred = 1.
      hr   = 1.

      IF ((patchtype<=1) .or. (is_dry_lake == 1)) THEN            !soil ground
         wx   = (wliq_soisno(1)/denh2o + wice_soisno(1)/denice)/dz_soisno(1)
         IF (porsl(1) < 1.e-6) THEN     !bed rock
            fac  = 0.001
         ELSE
            fac  = min(1.,wx/porsl(1))
            fac  = max( fac, 0.001 )
         ENDIF

#ifdef Campbell_SOIL_MODEL
         psit = psi0(1) * fac ** (- bsw(1) )   !psit = max(smpmin, psit)
#endif
         psit = max( -1.e8, psit )
         hr   = exp(psit/roverg/t_grnd)
         qred = (1.-fsno)*hr + fsno
      ENDIF

IF (.not. d_DEF_SPLIT_SOILSNOW) THEN
      CALL qsadv(t_grnd,forc_psrf,eg,degdT,qsatg,qsatgdT)

      qg     = qred*qsatg
      dqgdT  = qred*qsatgdT

      IF (qsatg > forc_q .and. forc_q > qg) THEN
        qg = forc_q; dqgdT = 0.
      ENDIF

      q_soil = qg
      q_snow = qg

ELSE
      CALL qsadv(t_soil,forc_psrf,eg,degdT,qsatg,qsatgdT)

      q_soil = hr*qsatg
      dqgdT  = (1.-fsno)*hr*qsatgdT

      IF(qsatg > forc_q .and. forc_q > q_soil)THEN
        q_soil = forc_q; dqgdT = 0.
      ENDIF

      CALL qsadv(t_snow,forc_psrf,eg,degdT,qsatg,qsatgdT)

      q_snow = qsatg
      dqgdT  = dqgdT + fsno*qsatgdT

      ! weighted average qg
      qg = (1.-fsno)*q_soil + fsno*q_snow
ENDIF

      ! calculate soil surface resistance (rss)
      ! ------------------------------------------------
      !NOTE: (1) DEF_RSS_SCHEME=0 means no rss considered
      !      (2) Do NOT calculate rss for the first timestep
      IF (d_DEF_RSS_SCHEME>0 .and. rss/=spval) THEN

         !NOTE: If the beta scheme is used, the rss is not soil resistance,
         !but soil beta factor (soil wetness relative to field capacity [0-1]).
         CALL SoilSurfaceResistance (nl_soil,forc_rhoair,hksati,porsl,psi0, &
#ifdef Campbell_SOIL_MODEL
                            bsw, &
#endif
                            dz_soisno,t_soisno,wliq_soisno,wice_soisno,fsno,qg,rss)
      ELSE
         IF (d_DEF_RSS_SCHEME == 4) THEN
            rss = 1.        !LP92
         ELSE
            rss = 0.        !the other RSS schemes
         ENDIF
      ENDIF

!=======================================================================
! [3] Compute sensible and latent fluxes and their derivatives with respect
!     to ground temperature using ground temperatures from previous time step.
! TODO: modify code description
!=======================================================================

      ! Always CALL GroundFluxes for bare ground CASE
      CALL GroundFluxes (zlnd,zsno,forc_hgt_u,forc_hgt_t,forc_hgt_q,forc_hpbl, &
                         forc_us,forc_vs,forc_t,forc_q,forc_rhoair,forc_psrf, &
                         ur,thm,th,thv,t_grnd,qg,rss,dqgdT,htvp, &
                         fsno,cgrnd,cgrndl,cgrnds, &
                         t_soil,t_snow,q_soil,q_snow, &
                         !taux,tauy,fseng,fevpg,tref,qref, &
                         taux,tauy,fseng,fseng_soil,fseng_snow, &
                         fevpg,fevpg_soil,fevpg_snow,tref,qref, &
                         z0m_g,z0h_g,zol_g,rib_g,ustar_g,qstar_g,tstar_g,fm_g,fh_g,fq_g)

      obu_g = forc_hgt_u / zol_g


!=======================================================================
! [4] Canopy temperature, fluxes from the canopy
!=======================================================================

IF ( patchtype==0.and.d_DEF_USE_LCT .or. patchtype>0 ) THEN

      sabv = sabvsun + sabvsha

      IF (lai+sai > 1e-6) THEN

         ! soil water stress factor on stomatal resistance
         CALL eroot (nl_soil,trsmx0,porsl,&
#ifdef Campbell_SOIL_MODEL
            bsw,&
#endif
            psi0,t_rootfr,dz_soisno,t_soisno,wliq_soisno,rootr,etrc,rstfac)

         ! fraction of sunlit and shaded leaves of canopy
         fsun = ( 1. - exp(-min(extkb*lai,40.))) / max( min(extkb*lai,40.), 1.e-6 )

         IF (coszen<=0.0 .or. sabv<1.) fsun = 0.5

         laisun = lai*fsun
         laisha = lai*(1-fsun)
         rstfacsun_out = rstfac
         rstfacsha_out = rstfac

         CALL LeafTemperature(ipatch,patchtype,1,deltim,csoilc   ,dewmx       ,htvp        ,&
                 lai         ,sai         ,htop        ,hbot        ,t_sqrtdi      ,&
                 t_effcon      ,t_vmax25      ,t_slti        ,t_hlti        ,t_shti        ,&
                 t_hhti        ,t_trda        ,t_trdm        ,t_trop        ,t_g1          ,&
                 t_g0          ,t_gradm       ,t_binter      ,t_extkn       ,extkb       ,&
                 extkd       ,forc_hgt_u  ,forc_hgt_t  ,forc_hgt_q  ,forc_us     ,&
                 forc_vs     ,thm         ,th          ,thv         ,forc_q      ,&
                 forc_psrf   ,forc_rhoair ,parsun      ,parsha      ,sabv        ,&
                 frl         ,fsun        ,thermk    ,rstfacsun_out,rstfacsha_out,&
                 gssun_out   ,gssha_out   ,forc_po2m   ,forc_pco2m  ,z0h_g       ,&
                 obu_g       ,ustar_g     ,zlnd        ,zsno        ,fsno        ,&
                 sigf        ,etrc        ,t_grnd      ,qg          ,rss         ,&
                 t_soil      ,t_snow      ,q_soil      ,q_snow      ,dqgdT       ,&
                 emg         ,tleaf       ,ldew        ,ldew_rain   ,ldew_snow   ,&
                 fwet_snow   ,taux        ,tauy        ,&
                 fseng       ,fseng_soil  ,fseng_snow  ,&
                 fevpg       ,fevpg_soil  ,fevpg_snow  ,&
                 cgrnd       ,cgrndl      ,cgrnds      ,&
                 tref        ,qref        ,rst         ,assim       ,respc       ,&
                 fsenl       ,fevpl       ,etr         ,dlrad       ,ulrad       ,&
                 z0m         ,zol         ,rib         ,ustar       ,qstar       ,&
                 tstar       ,fm          ,fh          ,fq          ,t_rootfr      ,&
                 t_kmax_sun    ,t_kmax_sha    ,t_kmax_xyl    ,t_kmax_root   ,t_psi50_sun   ,&
                 t_psi50_sha   ,t_psi50_xyl   ,t_psi50_root  ,t_ck          ,vegwp       ,&
                 gs0sun      ,gs0sha                                             ,&
                 assimsun_out,etrsun_out  ,assimsha_out             ,etrsha_out  ,&
!Ozone stress variables
                 o3coefv_sun ,o3coefv_sha ,o3coefg_sun ,o3coefg_sha ,&
                 lai_old     ,o3uptakesun ,o3uptakesha ,forc_ozone  ,&
!end ozone stress variables
!Ozone WUE stomata model parameter
                 t_lambda      ,&! Marginal water cost of carbon gain ((mol h2o) (mol co2)-1)
!End WUE stomata model parameter
                 forc_hpbl   ,&
                 qintr_rain  ,qintr_snow  ,t_precip    ,hprl        ,dheatl      ,&
                 smp         ,hk(1:)      ,hksati(1:)  ,rootflux(1:)             ,&
                  amx_hr,bmx_hr,cmx_hr,rmx_hr,drmx_hr,hx,hdx,xroot,zmm,qeroot_nl)
      ELSE
         tleaf         = forc_t
         laisun        = 0.
         laisha        = 0.
         ldew_rain     = 0.
         ldew_snow     = 0.
         fwet_snow     = 0.
         ldew          = 0.
         rstfacsun_out = 0.
         rstfacsha_out = 0.
         assimsun_out  = 0.
         assimsha_out  = 0.
         etrsun_out    = 0.
         etrsha_out    = 0.
         gssun_out     = 0.
         gssha_out     = 0.
         IF (d_DEF_USE_PLANTHYDRAULICS) THEN
            vegwp = -2.5e4
         ENDIF
      ENDIF

ENDIF


!=======================================================================
! [5] Ground temperature
!=======================================================================

      CALL GroundTemperature (patchtype,is_dry_lake,lb,nl_soil,deltim,&
                      capr,cnfac,vf_quartz,vf_gravels,vf_om,vf_sand,wf_gravels,wf_sand,&
                      porsl,psi0,&
#ifdef Campbell_SOIL_MODEL
                      bsw,&
#endif
                      csol,k_solids,dksatu,dksatf,dkdry,&
                      BA_alpha,BA_beta,&
                      sigf,dz_soisno,z_soisno,zi_soisno,&
                      t_soisno,t_grnd,t_soil,t_snow,wice_soisno,wliq_soisno,scv,snowdp,fsno,&
                      frl,dlrad,sabg,sabg_soil,sabg_snow,sabg_snow_lyr,&
                      fseng,fseng_soil,fseng_snow,fevpg,fevpg_soil,fevpg_snow,cgrnd,htvp,emg,&
                      imelt,snofrz,sm,xmf,fact,pg_rain,pg_snow,t_precip)

!=======================================================================
! [6] Correct fluxes to present soil temperature
!=======================================================================

      IF (.not.d_DEF_SPLIT_SOILSNOW) THEN
         t_grnd = t_soisno(lb)
         tinc   = t_soisno(lb) - t_soisno_bef(lb)
      ELSE
         t_grnd = fsno*t_soisno(lb) + (1.0-fsno)*t_soisno(1)
         tinc   = t_grnd - t_grnd_bef
      ENDIF

      fseng      = fseng      + tinc*cgrnds
      fseng_soil = fseng_soil + tinc*cgrnds
      fseng_snow = fseng_snow + tinc*cgrnds
      fevpg      = fevpg      + tinc*cgrndl
      fevpg_soil = fevpg_soil + tinc*cgrndl
      fevpg_snow = fevpg_snow + tinc*cgrndl

! calculation of evaporative potential; flux in kg m-2 s-1.
! egidif holds the excess energy IF all water is evaporated
! during the timestep. This energy is later added to the sensible heat flux.

      qseva = 0.
      qsubl = 0.
      qfros = 0.
      qsdew = 0.
      qseva_soil = 0.
      qsubl_soil = 0.
      qfros_soil = 0.
      qsdew_soil = 0.
      qseva_snow = 0.
      qsubl_snow = 0.
      qfros_snow = 0.
      qsdew_snow = 0.


IF (.not. d_DEF_SPLIT_SOILSNOW) THEN
      egsmax = (wice_soisno(lb)+wliq_soisno(lb)) / deltim
      egidif = max( 0., fevpg - egsmax )
      fevpg  = min( fevpg, egsmax )
      fseng  = fseng + htvp*egidif

      IF (fevpg >= 0.) THEN
! not allow for sublimation in melting (melting ==> evap. ==> sublimation)
         qseva = min(wliq_soisno(lb)/deltim, fevpg)
         qsubl = fevpg - qseva
      ELSE
         IF (t_grnd < tfrz) THEN
            qfros = abs(fevpg)
         ELSE
            qsdew = abs(fevpg)
         ENDIF
      ENDIF

ELSE
      IF (lb < 1) THEN   ! snow layer exist
         egsmax = (wice_soisno(lb)+wliq_soisno(lb)) / deltim
         egidif = max( 0., fevpg_snow - egsmax )
         fevpg_snow = min ( fevpg_snow, egsmax )
         fseng_snow = fseng_snow + htvp*egidif
      ELSE               ! no snow layer, attribute to soil
         fevpg_soil = fevpg_soil*(1.-fsno) + fevpg_snow*fsno
      ENDIF

      egsmax = (wice_soisno(1)+wliq_soisno(1)) / deltim
      egidif = max( 0., fevpg_soil - egsmax )
      fevpg_soil = min ( fevpg_soil, egsmax )
      fseng_soil = fseng_soil + htvp*egidif

      IF (lb < 1) THEN   ! snow layer exist
         fseng = fseng_soil*(1.-fsno) + fseng_snow*fsno
         fevpg = fevpg_soil*(1.-fsno) + fevpg_snow*fsno
      ELSE               ! no snow layer, attribute to soil
         fseng = fseng_soil; fseng_snow = 0.
         fevpg = fevpg_soil; fevpg_snow = 0.
      ENDIF

      IF(fevpg_snow >= 0.)THEN
! not allow for sublimation in melting (melting ==> evap. ==> sublimation)
         qseva_snow = min(wliq_soisno(lb)/deltim, fevpg_snow)
         qsubl_snow = fevpg_snow - qseva_snow
         qseva_snow = qseva_snow*fsno
         qsubl_snow = qsubl_snow*fsno
      ELSE
         ! snow temperature < tfrz
         IF(t_soisno(lb) < tfrz)THEN
            qfros_snow = abs(fevpg_snow*fsno)
         ELSE
            qsdew_snow = abs(fevpg_snow*fsno)
         ENDIF
      ENDIF

      IF(fevpg_soil >= 0.)THEN
! not allow for sublimation in melting (melting ==> evap. ==> sublimation)
         qseva_soil = min(wliq_soisno(1)/deltim, fevpg_soil)
         qsubl_soil = fevpg_soil - qseva_soil
      ELSE
         ! soil temperature < tfrz
         IF(t_soisno(1) < tfrz)THEN
            qfros_soil = abs(fevpg_soil)
         ELSE
            qsdew_soil = abs(fevpg_soil)
         ENDIF
      ENDIF

      IF (lb < 1) THEN ! snow layer exists
         qseva_soil = qseva_soil*(1.-fsno)
         qsubl_soil = qsubl_soil*(1.-fsno)
         qfros_soil = qfros_soil*(1.-fsno)
         qsdew_soil = qsdew_soil*(1.-fsno)
      ENDIF
ENDIF


! total fluxes to atmosphere
      fsena  = fsenl + fseng
      fevpa  = fevpl + fevpg
      lfevpa = hvap*fevpl + htvp*fevpg   ! W/m^2 (accounting for sublimation)

! ground heat flux
IF (.not.d_DEF_SPLIT_SOILSNOW) THEN
      fgrnd = sabg + dlrad*emg &
            - emg*stefnc*t_grnd_bef**4 &
            - emg*stefnc*t_grnd_bef**3*(4.*tinc) &
            - (fseng+fevpg*htvp) &
            + cpliq*pg_rain*(t_precip-t_grnd) &
            + cpice*pg_snow*(t_precip-t_grnd)
ELSE
      fgrnd = sabg + dlrad*emg &
            - fsno*emg*stefnc*t_snow**4 &
            - (1.-fsno)*emg*stefnc*t_soil**4 &
            - emg*stefnc*t_grnd_bef**3*(4.*tinc) &
            - (fseng+fevpg*htvp) &
            + cpliq*pg_rain*(t_precip-t_grnd) &
            + cpice*pg_snow*(t_precip-t_grnd)
ENDIF

! outgoing long-wave radiation from canopy + ground
      olrg = ulrad &
! for conservation we put the increase of ground longwave to outgoing
           + 4.*emg*stefnc*t_grnd_bef**3*tinc

! averaged bulk surface emissivity
      olrb = stefnc*t_grnd_bef**3*(4.*tinc)
      olru = ulrad + emg*olrb
      olrb = ulrad + olrb
      emis = olru / olrb

! radiative temperature
      IF (olrg < 0) THEN
         print *, "MOD_Thermal_CUDA.F90: Error! Negative outgoing longwave radiation flux: "
         print *, ipatch, olrg, tinc, ulrad
         print *, ipatch,errore,sabv,sabg,frl,olrg,fsenl,fseng,hvap*fevpl,htvp*fevpg,xmf,fgrnd
      ENDIF

      trad = (olrg/stefnc)**0.25

! additional variables required by WRF and RSM model
      IF (lai+sai <= 1e-6) THEN
         ustar = ustar_g
         tstar = tstar_g
         qstar = qstar_g
         rib   = rib_g
         zol   = zol_g
         z0m   = z0m_g
         fm    = fm_g
         fh    = fh_g
         fq    = fq_g
      ENDIF


!=======================================================================
! [7] energy balance error
!=======================================================================

      ! one way to check energy balance
      errore = sabv + sabg + frl - olrg - fsena - lfevpa - fgrnd - dheatl + hprl &
             + cpliq*pg_rain*(t_precip-t_grnd) + cpice*pg_snow*(t_precip-t_grnd)

      ! another way to check energy balance
      errore = sabv + sabg + frl - olrg - fsena - lfevpa - xmf - dheatl + hprl &
             + cpliq*pg_rain*(t_precip-t_grnd) + cpice*pg_snow*(t_precip-t_grnd)

      DO j = lb, nl_soil
         errore = errore - (t_soisno(j)-t_soisno_bef(j))/fact(j)
      ENDDO

  END SUBROUTINE THERMAL

END MODULE MOD_Thermal_CUDA
! ---------- EOP ------------
