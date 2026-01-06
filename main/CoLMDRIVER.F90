#include <define.h>

SUBROUTINE CoLMDRIVER (idate,deltim,dolai,doalb,dosst,oro)


!=======================================================================
!
!  CoLM MODEL DRIVER
!
!  Initial : Yongjiu Dai, 1999-2014
!  Revised : Hua Yuan, Shupeng Zhang, Nan Wei, Xingjie Lu, Zhongwang Wei, Yongjiu Dai
!            2014-2024
!
!=======================================================================

   USE MOD_Precision
   USE MOD_Const_Physical, only: tfrz, rgas, vonkar
   USE MOD_Const_LC
   USE MOD_Vars_Global
   USE MOD_Vars_TimeInvariants
   USE MOD_Vars_TimeVariables
   USE MOD_Vars_1DForcing
   USE MOD_Vars_1DFluxes
   USE MOD_LandPatch, only: numpatch,landpatch
   USE MOD_LandUrban, only: patch2urban
   USE MOD_Namelist, only: DEF_forcing, DEF_URBAN_RUN
   USE MOD_Forcing, only: forcmask_pch
   USE omp_lib

   IMPLICIT NONE

   integer,  intent(in) :: idate(3) ! model calendar for next time step (year, julian day, seconds)
   real(r8), intent(in) :: deltim   ! seconds in a time-step

   logical,  intent(in) :: dolai    ! true if time for time-varying vegetation parameter
   logical,  intent(in) :: doalb    ! true if time for surface albedo calculation
   logical,  intent(in) :: dosst    ! true if time for update sst/ice/snow

   real(r8), intent(inout) :: oro(numpatch)  ! ocean(0)/seaice(2)/ flag

   real(r8) :: deltim_phy
   integer  :: steps_in_one_deltim
   integer  :: i, m, u, k

! ======================================================================

      DO i = 1, numpatch

         ! Apply forcing mask
         IF (DEF_forcing%has_missing_value) THEN
            IF (.not. forcmask_pch(i)) CYCLE
         ENDIF

         ! Apply patch mask, but still run virtual 2m WMO patch (patch ipxstt=-1)
         IF (DEF_Output_2mWMO) THEN
            IF (.not. patchmask(i) .and. (landpatch%ipxstt(i)>0) ) CYCLE
         ELSE
            IF (.not. patchmask(i)) CYCLE
         ENDIF

         m = patchclass(i)

         steps_in_one_deltim = 1
         ! deltim need to be within 1800s for water body with snow in order to avoid large
         ! temperature fluctuations due to rapid snow heat conductance
         IF(m == WATERBODY) steps_in_one_deltim = ceiling(deltim/1800.)
         deltim_phy = deltim/steps_in_one_deltim

         ! For non urban patch or slab urban
         IF (.not.DEF_URBAN_RUN .or. m.ne.URBAN) THEN

            DO k = 1, steps_in_one_deltim
               !                ***** Call CoLM main program *****
               !
               CALL CoLMMAIN (  i,idate,         coszen(i),       deltim_phy,      &
               patchlonr(i),    patchlatr(i),    patchclass(i),   patchtype(i),    &
               doalb,           dolai,           dosst,           oro(i),          &

             ! SOIL INFORMATION AND LAKE DEPTH
               soil_s_v_alb(i), soil_d_v_alb(i), soil_s_n_alb(i), soil_d_n_alb(i), &
               vf_quartz(1:,i), vf_gravels(1:,i),vf_om(1:,i),     vf_sand(1:,i),   &
               wf_gravels(1:,i),wf_sand(1:,i),   porsl(1:,i),     psi0(1:,i),      &
               bsw(1:,i),       theta_r(1:,i),   fsatmax(i),      fsatdcf(i),      &
               topoweti(i),     alp_twi(i),      chi_twi(i),      mu_twi(i),       &
               hksati(1:,i),    csol(1:,i),      k_solids(1:,i),  dksatu(1:,i),    &
               dksatf(1:,i),    dkdry(1:,i),     BA_alpha(1:,i),  BA_beta(1:,i),   &
               rootfr(1:,m),    lakedepth(i),    dz_lake(1:,i),   elvstd(i),       &
               BVIC(i),                                                            &

             ! VEGETATION INFORMATION
               htop(i),         hbot(i),         sqrtdi(m),                        &
               effcon(m),       vmax25(m),       c3c4(m),                          &
               kmax_sun(m),     kmax_sha(m),     kmax_xyl(m),     kmax_root(m),    &
               psi50_sun(m),    psi50_sha(m),    psi50_xyl(m),    psi50_root(m),   &
               ck(m),           slti(m),         hlti(m),         shti(m),         &
               hhti(m),         trda(m),         trdm(m),         trop(m),         &
               g1(m),           g0(m),           gradm(m),        binter(m),       &
               extkn(m),        chil(m),         rho(1:,1:,m),    tau(1:,1:,m),    &

             ! ATMOSPHERIC FORCING
               forc_pco2m(i),   forc_po2m(i),    forc_us(i),      forc_vs(i),      &
               forc_t(i),       forc_q(i),       forc_prc(i),     forc_prl(i),     &
               forc_rain(i),    forc_snow(i),    forc_psrf(i),    forc_pbot(i),    &
               forc_sols(i),    forc_soll(i),    forc_solsd(i),   forc_solld(i),   &
               forc_frl(i),     forc_hgt_u(i),   forc_hgt_t(i),   forc_hgt_q(i),   &
               forc_rhoair(i),                                                     &
             ! CBL height forcing
               forc_hpbl(i),                                                       &
             ! Aerosol deposition
               forc_aerdep(:,i),                                                   &

             ! LAND SURFACE VARIABLES REQUIRED FOR RESTART
               z_sno(maxsnl+1:,i),               dz_sno(maxsnl+1:,i),              &
               t_soisno(maxsnl+1:,i),            wliq_soisno(maxsnl+1:,i),         &
               wice_soisno(maxsnl+1:,i),         smp(1:,i),       hk(1:,i),        &
               t_grnd(i),       tleaf(i),        ldew(i),         ldew_rain(i),    &
               ldew_snow(i),    fwet_snow(i),    sag(i),          scv(i),          &
               snowdp(i),       fveg(i),         fsno(i),         sigf(i),         &
               green(i),        lai(i),          sai(i),          alb(1:,1:,i),    &
               ssun(1:,1:,i),   ssha(1:,1:,i),   ssoi(:,:,i),     ssno(:,:,i),     &
               thermk(i),       extkb(i),        extkd(i),        vegwp(1:,i),     &
               gs0sun(i),       gs0sha(i),       &
             ! Ozone Stress Variables
               lai_old(i),      o3uptakesun(i),  o3uptakesha(i),  forc_ozone(i),   &
             ! End ozone stress variables
             ! WUE stomata model parameter
               lambda(m),                                                          &
             ! End WUE model parameter
               zwt(i),          wdsrf(i),        wa(i),           wetwat(i),       &
               t_lake(1:,i),    lake_icefrac(1:,i),               savedtke1(i),    &

             ! SNICAR snow model related
               snw_rds(:,i),    ssno_lyr(:,:,:,i),                                 &
               mss_bcpho(:,i),  mss_bcphi(:,i),  mss_ocpho(:,i),  mss_ocphi(:,i),  &
               mss_dst1(:,i),   mss_dst2(:,i),   mss_dst3(:,i),   mss_dst4(:,i),   &

             ! additional diagnostic variables for output
               laisun(i),       laisha(i),       rootr(1:,i),     rootflux(1:,i),  &
               rstfacsun_out(i),rstfacsha_out(i),gssun_out(i),    gssha_out(i),    &
               assimsun_out(i), etrsun_out(i),   assimsha_out(i), etrsha_out(i),   &
               h2osoi(1:,i),    wat(i),          rss(i),          &

             ! FLUXES
               taux(i),         tauy(i),         fsena(i),        fevpa(i),        &
               lfevpa(i),       fsenl(i),        fevpl(i),        etr(i),          &
               fseng(i),        fevpg(i),        olrg(i),         fgrnd(i),        &
               trad(i),         tref(i),         qref(i),         t2m_wmo(i),      &
               frcsat(i),       rsur(i),         &
               rsur_se(i),      rsur_ie(i),      rnof(i),         qintr(i),        &
               qinfl(i),        qdrip(i),        rst(i),          assim(i),        &
               respc(i),        sabvsun(i),      sabvsha(i),      sabg(i),         &
               sr(i),           solvd(i),        solvi(i),        solnd(i),        &
               solni(i),        srvd(i),         srvi(i),         srnd(i),         &
               srni(i),         solvdln(i),      solviln(i),      solndln(i),      &
               solniln(i),      srvdln(i),       srviln(i),       srndln(i),       &
               srniln(i),       qcharge(i),      xerr(i),         zerr(i),         &

             ! TUNABLE modle constants
               zlnd,            zsno,            csoilc,          dewmx,           &
               ! 'wtfact' is updated to gridded 'fsatmax' data.
               capr,            cnfac,           ssi,             wimp,            &
               pondmx,          smpmax,          smpmin,          trsmx0,          &
               tcrit,           &

             ! additional variables required by coupling with WRF model
               emis(i),         z0m(i),          zol(i),          rib(i),          &
               ustar(i),        qstar(i),        tstar(i),                         &
               fm(i),           fh(i),           fq(i)                             )

            ENDDO
         ENDIF
      ENDDO

END SUBROUTINE CoLMDRIVER
! ---------- EOP ------------
