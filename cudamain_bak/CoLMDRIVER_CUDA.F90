#include <define.h>

SUBROUTINE CoLMDRIVER_CUDA (idate,deltim,dolai,doalb,dosst,oro)


!=======================================================================
!
!  CoLM MODEL DRIVER
!
!  Initial : Yongjiu Dai, 1999-2014
!  Revised : Hua Yuan, Shupeng Zhang, Nan Wei, Xingjie Lu, Zhongwang Wei, Yongjiu Dai
!            2014-2024
!
!=======================================================================
   USE cudafor
   USE MOD_Init_CUDA
   USE MOD_ConstVars_CUDA
   USE MOD_AllocatableVars_CUDA
   IMPLICIT NONE
   integer,  intent(in) :: idate(3) ! model calendar for next time step (year, julian day, seconds)
   real(r8), intent(in) :: deltim   ! seconds in a time-step
   logical,  intent(in) :: dolai    ! true if time for time-varying vegetation parameter
   logical,  intent(in) :: doalb    ! true if time for surface albedo calculation
   logical,  intent(in) :: dosst    ! true if time for update sst/ice/snow
   real(r8), intent(inout) :: oro(numpatch)  ! ocean(0)/seaice(2)/ flag

   real :: start, finish
   real :: driver_start, driver_finish
   integer  :: i, m, u, k
! ======================================================================

   call cpu_time(driver_start)
   call cpu_time(start)
   call const_var_init(idate, deltim, dolai, doalb, dosst)
   call allocate_var_init(oro(:))

   call cpu_time(finish)
   print '(\"[var_init] Time = \",f9.6,\" seconds.\")', finish - start

! running kernel
   call cpu_time(start)
   call CoLMDRIVER_Init_CUDA<<<((numpatch-1)/blockDim1+1), blockDim1>>>()
   ierr = cudaDeviceSynchronize()
   if (ierr /= cudaSuccess) write(*,*) 'Sync Error:', cudaGetErrorString(ierr)
   call cpu_time(finish)
   print '(\"[CoLMDRIVER_Init_CUDA] Time = \",f9.6,\" seconds.\")', finish - start

   call cpu_time(start)
   call CoLMMAIN_Init_CUDA<<<((numpatch-1)/blockDim1+1), blockDim1>>>()
   ierr = cudaDeviceSynchronize()
   if (ierr /= cudaSuccess) write(*,*) 'Sync Error:', cudaGetErrorString(ierr)
   call cpu_time(finish)
   print '(\"[CoLMMAIN_Init_CUDA] Time = \",f9.6,\" seconds.\")', finish - start

   call cpu_time(start)
   call CoLMMAIN_Solar_CUDA<<<((numpatch-1)/blockDim1+1), blockDim1>>>()
   ierr = cudaDeviceSynchronize()
   if (ierr /= cudaSuccess) write(*,*) 'Sync Error:', cudaGetErrorString(ierr)
   call cpu_time(finish)
   print '(\"[CoLMMAIN_Solar_CUDA] Time = \",f9.6,\" seconds.\")', finish - start

   call cpu_time(start)
   call CoLMMAIN_498_CUDA<<<((numpatch-1)/blockDim1+1), blockDim1>>>()
   ierr = cudaDeviceSynchronize()
   if (ierr /= cudaSuccess) write(*,*) 'Sync Error:', cudaGetErrorString(ierr)
   call cpu_time(finish)
   print '(\"[CoLMMAIN_498_CUDA] Time = \",f9.6,\" seconds.\")', finish - start

   call cpu_time(start)
   call CoLMMAIN_Canopy_CUDA<<<((numpatch-1)/blockDim1+1), blockDim1>>>()
   ierr = cudaDeviceSynchronize()
   if (ierr /= cudaSuccess) write(*,*) 'Sync Error:', cudaGetErrorString(ierr)
   call cpu_time(finish)
   print '(\"[CoLMMAIN_Canopy_CUDA] Time = \",f9.6,\" seconds.\")', finish - start

   call cpu_time(start)
   call CoLMMAIN_Thermal_CUDA<<<((numpatch-1)/blockDim2+1), blockDim2>>>()
   ierr = cudaDeviceSynchronize()
   if (ierr /= cudaSuccess) write(*,*) 'Sync Error:', cudaGetErrorString(ierr)
   call cpu_time(finish)
   print '(\"[CoLMMAIN_Thermal_CUDA] Time = \",f9.6,\" seconds.\")', finish - start

   call cpu_time(start)
   call CoLMMAIN_Water_CUDA<<<((numpatch-1)/blockDim3+1), blockDim3>>>()
   ierr = cudaDeviceSynchronize()
   if (ierr /= cudaSuccess) write(*,*) 'Sync Error:', cudaGetErrorString(ierr)
   call cpu_time(finish)
   print '(\"[CoLMMAIN_Water_CUDA] Time = \",f9.6,\" seconds.\")', finish - start

   call cpu_time(start)
   call CoLMMAIN_WaterBodies_CUDA<<<((numpatch-1)/blockDim1+1), blockDim1>>>()
   ierr = cudaDeviceSynchronize()
   if (ierr /= cudaSuccess) write(*,*) 'Sync Error:', cudaGetErrorString(ierr)
   call cpu_time(finish)
   print '(\"[CoLMMAIN_WaterBodies_CUDA] Time = \",f9.6,\" seconds.\")', finish - start

   call cpu_time(start)
   call CoLMMAIN_Preparation_CUDA<<<((numpatch-1)/blockDim1+1), blockDim1>>>()
   ierr = cudaDeviceSynchronize()
   if (ierr /= cudaSuccess) write(*,*) 'Sync Error:', cudaGetErrorString(ierr)
   call cpu_time(finish)
   print '(\"[CoLMMAIN_Preparation_CUDA] Time = \",f9.6,\" seconds.\")', finish - start

   call allocate_var_deinit
   call cpu_time(driver_finish)
   print '(\"[driver] Time = \",f9.6,\" seconds.\")', driver_finish - driver_start

   ! print *, rootflux(:,10)

END SUBROUTINE CoLMDRIVER_CUDA

attributes(global) SUBROUTINE CoLMDRIVER_Init_CUDA ()

   USE cudafor
   USE MOD_ConstVars_CUDA
   USE MOD_AllocatableVars_CUDA

   IMPLICIT NONE

! ----------------------- Local  Variables -----------------------------
   real(r8) :: deltim_phy
   integer  :: steps_in_one_deltim
   integer  :: i, m, u, k

   i = threadIdx%x + (blockIdx%x - 1) * blockDim%x
   if (i > d_numpatch) then
      return
   endif

   ! Apply forcing mask
   IF (d_DEF_forcing%has_missing_value) THEN
      IF (.not. forcmask_pch(i)) return
   ENDIF

   ! Apply patch mask
   IF (.not. patchmask(i)) return
   l_run_mask(i) = 1

   m = patchclass(i)
   steps_in_one_deltim = 1
   ! deltim need to be within 1800s for water body with snow in order to avoid large
   ! temperature fluctuations due to rapid snow heat conductance
   IF (m == WATERBODY .and. snowdp(i) > 0.0) steps_in_one_deltim = ceiling(d_deltim/1800.)
   l_steps_in_one_deltim(i) = steps_in_one_deltim
   IF (steps_in_one_deltim /= 1) print *, "ERROR steps_in_one_deltim /= 1", i

   deltim_phy = d_deltim/steps_in_one_deltim
   l_deltim_phy(i) = deltim_phy

END SUBROUTINE CoLMDRIVER_Init_CUDA

attributes(global) SUBROUTINE CoLMMAIN_Init_CUDA ()

   USE cudafor
   USE MOD_ConstVars_CUDA
   USE MOD_AllocatableVars_CUDA

   IMPLICIT NONE

! Variables required for restart run
!-----------------------------------------------------------------------
   real(r8) :: &
        z_soisno   (maxsnl+1:nl_soil) ,&! layer depth (m)
        dz_soisno  (maxsnl+1:nl_soil)   ! layer thickness (m)

! ----------------------- Local  Variables -----------------------------
   real(r8) :: forc_aer           ( 14 )  !aerosol deposition from atmosphere model (grd,aer) [kg m-1 s-1]
   real(r8) :: snofrz       (maxsnl+1:0)  !snow freezing rate (col,lyr) [kg m-2 s-1]
   integer  :: i, m, u, k

   i = threadIdx%x + (blockIdx%x - 1) * blockDim%x
   if (i > d_numpatch) then
      return
   endif
   if (l_run_mask(i) /= 1) then
      return
   endif
   m = patchclass(i)

   z_soisno (maxsnl+1:0) = z_sno (maxsnl+1:0,i)
   z_soisno (1:nl_soil ) = d_z_soi (1:nl_soil )
   dz_soisno(maxsnl+1:0) = dz_sno(maxsnl+1:0,i)
   dz_soisno(1:nl_soil ) = d_dz_soi(1:nl_soil )
   ! SNICAR initialization
   ! ---------------------
   ! snow freezing rate (col,lyr) [kg m-2 s-1]
   snofrz(:) = 0.
   ! aerosol deposition value
   IF (d_DEF_Aerosol_Readin) THEN
      forc_aer(:) = forc_aerdep(:,i)   ! read from outside forcing file
   ELSE
      forc_aer(:) = 0.                 ! manual setting
      !forc_aer(:) = 4.2E-7            ! manual setting
   ENDIF

   l_z_soisno (:,i) = z_soisno (:)
   l_dz_soisno(:,i) = dz_soisno(:)

   l_snofrz   (:,i) = snofrz(:)
   l_forc_aer (:,i) = forc_aer(:)

END SUBROUTINE CoLMMAIN_Init_CUDA

attributes(global) SUBROUTINE CoLMMAIN_Solar_CUDA ()

   USE cudafor
   USE MOD_ConstVars_CUDA
   USE MOD_AllocatableVars_CUDA

   USE MOD_NetSolar_CUDA
   USE MOD_RainSnowTemp_CUDA

   IMPLICIT NONE

   integer  :: i, m

   i = threadIdx%x + (blockIdx%x - 1) * blockDim%x
   if (i > d_numpatch) then
      return
   endif
   if (l_run_mask(i) /= 1) then
      return
   endif
   m = patchclass(i)

!======================================================================
!  [1] Solar absorbed by vegetation and ground
!      and precipitation information (rain/snow fall and precip temperature
!======================================================================
   CALL netsolar (i,l_deltim_phy(i),patchlonr(i),patchtype(i),&
                  forc_sols(i),forc_soll(i),forc_solsd(i),forc_solld(i),&
                  alb(:,:,i),ssun(:,:,i),ssha(:,:,i),lai(i),sai(i),&
                  d_rho(1:,1:,m),d_tau(1:,1:,m),ssoi(:,:,i),ssno(:,:,i),ssno_lyr(:,:,:,i),fsno(i),&
                  l_parsun(i),l_parsha(i),sabvsun(i),sabvsha(i),sabg(i),l_sabg_soil(i),l_sabg_snow(i),l_sabg_snow_lyr(:,i),&
                  sr(i),solvd(i),solvi(i),solnd(i),solni(i),srvd(i),srvi(i),srnd(i),srni(i),&
                  solvdln(i),solviln(i),solndln(i),solniln(i),srvdln(i),srviln(i),srndln(i),srniln(i))
   CALL rain_snow_temp (patchtype(i), &
                        forc_t(i),forc_q(i),forc_psrf(i),forc_prc(i),forc_prl(i),forc_us(i),forc_vs(i),d_tcrit,&
                        l_prc_rain(i),l_prc_snow(i),l_prl_rain(i),l_prl_snow(i),l_t_precip(i),l_bifall(i))
   forc_rain(i) = l_prc_rain(i) + l_prl_rain(i)
   forc_snow(i) = l_prc_snow(i) + l_prl_snow(i)

END SUBROUTINE CoLMMAIN_Solar_CUDA

attributes(global) SUBROUTINE CoLMMAIN_498_CUDA ()

   USE cudafor
   USE MOD_ConstVars_CUDA
   USE MOD_AllocatableVars_CUDA

   IMPLICIT NONE

   integer  :: i, j, m
   integer  :: t_snl

   i = threadIdx%x + (blockIdx%x - 1) * blockDim%x
   if (i > d_numpatch) then
      return
   endif
   if (l_run_mask(i) /= 1) then
      return
   endif
   m = patchclass(i)

!======================================================================
   IF (d_DEF_USE_Dynamic_Lake .and. (patchtype(i) == 4) .and. ((wdsrf(i) < 100.) .or. (zwt(i) > 0.))) THEN
      l_is_dry_lake(i) = 1
   ELSE
      l_is_dry_lake(i) = 0
   ENDIF
   ! l_is_dry_lake(i) = d_DEF_USE_Dynamic_Lake .and. (patchtype(i) == 4) .and. ((wdsrf(i) < 100.) .or. (zwt(i) > 0.))
                                                !         / SOIL GROUND          (patchtype = 0)
   IF (.not. ((patchtype(i) <= 2) .or. (l_is_dry_lake(i) == 1))) THEN ! <=== is - URBAN and BUILT-UP   (patchtype = 1)
                                                !         \ WETLAND              (patchtype = 2)
                                                !           Dry Lake             (patchtype = 4)
      return
   ENDIF
! NOTE: PFT and PC are only for soil patches, i.e., patchtype=0.
!======================================================================
                     ! initial set
   l_scvold(i) = scv(i)    ! snow mass at previous time step
   t_snl = 0
   DO j=maxsnl+1,0
      IF(wliq_soisno(j,i)+wice_soisno(j,i)>0.) t_snl=t_snl-1
   ENDDO
   l_zi_soisno(0,i)=0.
   IF (t_snl < 0) THEN
      DO j = -1, t_snl, -1
         l_zi_soisno(j,i)=l_zi_soisno(j+1,i)-l_dz_soisno(j+1,i)
      ENDDO
   ENDIF
   DO j = 1,nl_soil
      l_zi_soisno(j,i)=l_zi_soisno(j-1,i)+l_dz_soisno(j,i)
   ENDDO
   l_totwb(i) = ldew(i) + scv(i) + sum(wice_soisno(1:,i)+wliq_soisno(1:,i)) + wa(i)
   IF (d_DEF_USE_VariablySaturatedFlow) THEN
      l_totwb(i) = l_totwb(i) + wdsrf(i)
      IF (patchtype(i) == 2) THEN
         l_totwb(i) = l_totwb(i) + wetwat(i)
      ENDIF
   ENDIF
   l_fiold(:,i) = 0.0
   IF (t_snl <0 ) THEN
      l_fiold(t_snl+1:0,i)=wice_soisno(t_snl+1:0,i)/(wliq_soisno(t_snl+1:0,i)+wice_soisno(t_snl+1:0,i))
   ENDIF
   l_snl(i) = t_snl

END SUBROUTINE CoLMMAIN_498_CUDA

attributes(global) SUBROUTINE CoLMMAIN_Canopy_CUDA ()

   USE cudafor
   USE MOD_ConstVars_CUDA
   USE MOD_AllocatableVars_CUDA

   USE MOD_LeafInterception_CUDA
   USE MOD_NewSnow_CUDA
   USE MOD_Thermal_CUDA

   IMPLICIT NONE

   integer  :: i, j, m
   integer  :: t_snl        ! number of snow layers

   i = threadIdx%x + (blockIdx%x - 1) * blockDim%x
   if (i > d_numpatch) then
      return
   endif
   if (l_run_mask(i) /= 1) then
      return
   endif
   m = patchclass(i)

!======================================================================
   IF (d_DEF_USE_Dynamic_Lake .and. (patchtype(i) == 4) .and. ((wdsrf(i) < 100.) .or. (zwt(i) > 0.))) THEN
      l_is_dry_lake(i) = 1
   ELSE
      l_is_dry_lake(i) = 0
   ENDIF
   ! l_is_dry_lake(i) = d_DEF_USE_Dynamic_Lake .and. (patchtype(i) == 4) .and. ((wdsrf(i) < 100.) .or. (zwt(i) > 0.))
                                                !         / SOIL GROUND          (patchtype = 0)
   IF (.not. ((patchtype(i) <= 2) .or. (l_is_dry_lake(i) == 1))) THEN ! <=== is - URBAN and BUILT-UP   (patchtype = 1)
                                                !         \ WETLAND              (patchtype = 2)
                                                !           Dry Lake             (patchtype = 4)
      return
   ENDIF
   t_snl = l_snl(i)
!----------------------------------------------------------------------
! [2] Canopy interception and precipitation onto ground surface
!----------------------------------------------------------------------
   ! qflx_irrig_sprinkler = 0._r8
   ! IF (patchtype(i) == 0) THEN
      CALL LEAF_interception_wrap (l_deltim_phy(i),d_dewmx,forc_us(i),forc_vs(i),d_chil(m),sigf(i),lai(i),sai(i),forc_t(i), tleaf(i),&
                  l_prc_rain(i),l_prc_snow(i),l_prl_rain(i),l_prl_snow(i),l_bifall(i),&
                  ldew(i),ldew_rain(i),ldew_snow(i),z0m(i),forc_hgt_u(i),l_pg_rain(i),l_pg_snow(i),qintr(i),l_qintr_rain(i),l_qintr_snow(i))
   ! ELSE
   !    CALL LEAF_interception_wrap (deltim,dewmx,forc_us,forc_vs,chil,sigf,lai,sai,forc_t, tleaf,&
   !                prc_rain,prc_snow,prl_rain,prl_snow,bifall,&
   !                ldew,ldew_rain,ldew_snow,z0m,forc_hgt_u,pg_rain,pg_snow,qintr,qintr_rain,qintr_snow)
   ! ENDIF
   qdrip(i) = l_pg_rain(i) + l_pg_snow(i)
!----------------------------------------------------------------------
! [3] Initialize new snow nodes for snowfall / sleet
!----------------------------------------------------------------------
   l_snl_bef(i) = t_snl
   CALL newsnow (patchtype(i),maxsnl,l_deltim_phy(i),t_grnd(i),l_pg_rain(i),l_pg_snow(i),l_bifall(i),&
                  l_t_precip(i),l_zi_soisno(:0,i),l_z_soisno(:0,i),l_dz_soisno(:0,i),t_soisno(:0,i),&
                  wliq_soisno(:0,i),wice_soisno(:0,i),l_fiold(:0,i),t_snl,sag(i),scv(i),snowdp(i),fsno(i),wetwat(i))
   l_snl(i) = t_snl
END SUBROUTINE CoLMMAIN_Canopy_CUDA

attributes(global) SUBROUTINE CoLMMAIN_Thermal_CUDA ()

   USE cudafor
   USE MOD_ConstVars_CUDA
   USE MOD_AllocatableVars_CUDA

   USE MOD_LeafInterception_CUDA
   USE MOD_NewSnow_CUDA
   USE MOD_Thermal_CUDA

   IMPLICIT NONE

   integer  :: i, j, m
   integer  :: t_snl                      ,&! number of snow layers
               t_imelt(maxsnl+1:nl_soil)  ,&! flag for: melting=1, freezing=2, Nothing happened=0
               t_lb ,t_lbsn                 ! lower bound of arrays

   i = threadIdx%x + (blockIdx%x - 1) * blockDim%x
   if (i > d_numpatch) then
      return
   endif
   if (l_run_mask(i) /= 1) then
      return
   endif
   m = patchclass(i)

!======================================================================
   ! l_is_dry_lake(i) = d_DEF_USE_Dynamic_Lake .and. (patchtype(i) == 4) .and. ((wdsrf(i) < 100.) .or. (zwt(i) > 0.))
                                                !         / SOIL GROUND          (patchtype = 0)
   IF (.not. ((patchtype(i) <= 2) .or. (l_is_dry_lake(i) == 1))) THEN ! <=== is - URBAN and BUILT-UP   (patchtype = 1)
                                                !         \ WETLAND              (patchtype = 2)
                                                !           Dry Lake             (patchtype = 4)
      return
   ENDIF

!----------------------------------------------------------------------
! [4] Energy and Water balance
!----------------------------------------------------------------------
   t_snl = l_snl(i)

   t_lb   = t_snl + 1           !lower bound of array
   t_lbsn = min(t_lb,0)
   CALL THERMAL (i,patchtype(i)         ,l_is_dry_lake(i),t_lb                ,l_deltim_phy(i)            ,&
         d_trsmx0            ,d_zlnd              ,d_zsno              ,d_csoilc            ,&
         d_dewmx             ,d_capr              ,d_cnfac             ,vf_quartz(1:,i)         ,&
         vf_gravels(1:,i)        ,vf_om(1:,i)             ,vf_sand(1:,i)           ,wf_gravels(1:,i)        ,&
         wf_sand(1:,i)           ,csol(1:,i)              ,porsl(1:,i)             ,psi0(1:,i)              ,&
         bsw(1:,i)               ,&
         k_solids(1:,i)          ,dksatu(1:,i)            ,dksatf(1:,i)            ,dkdry(1:,i)             ,&
         BA_alpha(1:,i)          ,BA_beta(1:,i)           ,lai(i)               ,laisun(i)            ,&
         laisha(i)            ,sai(i)               ,htop(i)              ,hbot(i)              ,&
         d_sqrtdi(m)            ,d_rootfr(1:,m)            ,rstfacsun_out(i)     ,rstfacsha_out(i)     ,&
         rss(i)               ,gssun_out(i)         ,gssha_out(i)         ,assimsun_out(i)      ,&
         etrsun_out(i)        ,assimsha_out(i)      ,etrsha_out(i)        ,&
         d_effcon(m)            ,d_vmax25(m)            ,hksati(1:,i)            ,smp(1:,i) ,hk(1:,i)           ,&
         d_kmax_sun(m)          ,d_kmax_sha(m)          ,d_kmax_xyl(m)          ,d_kmax_root(m)         ,&
         d_psi50_sun(m)         ,d_psi50_sha(m)         ,d_psi50_xyl(m)         ,d_psi50_root(m)        ,&
         d_ck(m)                ,vegwp(1:,i)             ,gs0sun(i)            ,gs0sha(i)            ,&
         !Ozone stress variables
         lai_old(i)           ,o3uptakesun(i)       ,o3uptakesha(i)       ,forc_ozone(i)        ,&
         !End ozone stress variables
         !WUE stomata model parameter
         d_lambda(m)      ,&! Marginal water cost of carbon gain ((mol h2o) (mol co2)-1)
         !WUE stomata model parameter
         d_slti(m)              ,d_hlti(m)              ,d_shti(m)              ,d_hhti(m)              ,&
         d_trda(m)              ,d_trdm(m)              ,d_trop(m)              ,d_g1(m)                ,&
         d_g0(m)                ,d_gradm(m)             ,d_binter(m)            ,d_extkn(m)             ,&
         forc_hgt_u(i)        ,forc_hgt_t(i)        ,forc_hgt_q(i)        ,forc_us(i)           ,&
         forc_vs(i)           ,forc_t(i)            ,forc_q(i)            ,forc_rhoair(i)       ,&
         forc_psrf(i)         ,forc_pco2m(i)        ,forc_hpbl(i)         ,forc_po2m(i)         ,&
         coszen(i)            ,l_parsun(i)            ,l_parsha(i)            ,sabvsun(i)           ,&
         sabvsha(i)           ,sabg(i)              ,l_sabg_soil(i)         ,l_sabg_snow(i)         ,&
         forc_frl(i)          ,extkb(i)             ,extkd(i)             ,thermk(i)            ,&
         fsno(i)              ,sigf(i)              ,l_dz_soisno(t_lb:,i)    ,l_z_soisno(t_lb:,i)     ,&
         l_zi_soisno(t_lb-1:,i)  ,tleaf(i)             ,t_soisno(t_lb:,i)     ,wice_soisno(t_lb:,i)  ,&
         wliq_soisno(t_lb:,i)  ,ldew(i)              ,ldew_rain(i)         ,ldew_snow(i)         ,&
         fwet_snow(i)         ,scv(i)               ,snowdp(i)            ,t_imelt(t_lb:)        ,&
         taux(i)              ,tauy(i)              ,fsena(i)             ,fevpa(i)             ,&
         lfevpa(i)            ,fsenl(i)             ,fevpl(i)             ,etr(i)               ,&
         fseng(i)             ,fevpg(i)             ,olrg(i)              ,fgrnd(i)             ,&
         rootr(1:,i)             ,rootflux(1:,i)          ,l_qseva(i)             ,l_qsdew(i)             ,&
         l_qsubl(i)             ,l_qfros(i)             ,l_qseva_soil(i)        ,l_qsdew_soil(i)        ,&
         l_qsubl_soil(i)        ,l_qfros_soil(i)        ,l_qseva_snow(i)        ,l_qsdew_snow(i)        ,&
         l_qsubl_snow(i)        ,l_qfros_snow(i)        ,l_sm(i)                ,tref(i)              ,&
         qref(i)              ,trad(i)              ,rst(i)               ,assim(i)             ,&
         respc(i)             ,l_errore(i)            ,emis(i)              ,z0m(i)               ,&
         zol(i)               ,rib(i)               ,ustar(i)             ,qstar(i)             ,&
         tstar(i)             ,fm(i)                ,fh(i)                ,fq(i)                ,&
         l_pg_rain(i)           ,l_pg_snow(i)           ,l_t_precip(i)          ,l_qintr_rain(i)        ,&
         l_qintr_snow(i)        ,l_snofrz(t_lbsn:0,i)    ,l_sabg_snow_lyr(t_lb:1,i)                   ,&
         l_amx_hr(:,i),l_bmx_hr(:,i),l_cmx_hr(:,i),l_rmx_hr(:,i),l_drmx_hr(:,i),l_x(:,i),l_dx(:,i),l_xroot(:,i),l_zmm(:,i),l_qeroot_nl(:,i))
   l_snl(i) = t_snl
   l_imelt(:,i) = t_imelt(:)
   l_lb(i) = t_lb
   l_lbsn(i) = t_lbsn
END SUBROUTINE CoLMMAIN_Thermal_CUDA

attributes(global) SUBROUTINE CoLMMAIN_Water_CUDA ()

   USE cudafor
   USE MOD_ConstVars_CUDA
   USE MOD_AllocatableVars_CUDA

   USE MOD_SoilSnowHydrology_CUDA
   USE MOD_SnowLayersCombineDivide_CUDA
   USE MOD_Lake_CUDA

   IMPLICIT NONE

   integer  :: i, j, m
   integer  :: t_snl                      ,&! number of snow layers
               t_imelt(maxsnl+1:nl_soil)  ,&! flag for: melting=1, freezing=2, Nothing happened=0
               t_lb ,t_lbsn                 ! lower bound of arrays

   i = threadIdx%x + (blockIdx%x - 1) * blockDim%x
   if (i > d_numpatch) then
      return
   endif
   if (l_run_mask(i) /= 1) then
      return
   endif
   m = patchclass(i)

!======================================================================
   ! l_is_dry_lake(i) = d_DEF_USE_Dynamic_Lake .and. (patchtype(i) == 4) .and. ((wdsrf(i) < 100.) .or. (zwt(i) > 0.))
                                                !         / SOIL GROUND          (patchtype = 0)
   IF (.not. ((patchtype(i) <= 2) .or. (l_is_dry_lake(i) == 1))) THEN ! <=== is - URBAN and BUILT-UP   (patchtype = 1)
                                                !         \ WETLAND              (patchtype = 2)
                                                !           Dry Lake             (patchtype = 4)
      return
   ENDIF

!----------------------------------------------------------------------
! [4] Energy and Water balance
!----------------------------------------------------------------------
   t_snl = l_snl(i)
   t_imelt(:) = l_imelt(:,i)
   t_lb   = l_lb(i)
   t_lbsn = l_lbsn(i)
   IF (.not. d_DEF_USE_VariablySaturatedFlow) THEN
      CALL WATER_2014 (i,patchtype(i)  ,t_lb                ,nl_soil           ,&
            l_deltim_phy(i)            ,l_z_soisno(t_lb:,i)     ,l_dz_soisno(t_lb:,i)    ,l_zi_soisno(t_lb-1:,i)  ,&
            bsw(:,i)               ,porsl(:,i)             ,psi0(:,i)              ,hksati(:,i)            ,&
            theta_r(:,i)           ,fsatmax(i)           ,fsatdcf(i)           ,topostd(i)           ,&
            BVIC(i)              ,rootr(:,i)             ,rootflux(:,i)          ,t_soisno(t_lb:,i)     ,&
            wliq_soisno(t_lb:,i)  ,wice_soisno(t_lb:,i)  ,smp(:,i)               ,hk(:,i)                ,&
            l_pg_rain(i)           ,l_sm(i)                ,etr(i)               ,l_qseva(i)             ,&
            l_qsdew(i)             ,l_qsubl(i)             ,l_qfros(i)             ,l_qseva_soil(i)        ,&
            l_qsdew_soil(i)        ,l_qsubl_soil(i)        ,l_qfros_soil(i)        ,l_qseva_snow(i)        ,&
            l_qsdew_snow(i)        ,l_qsubl_snow(i)        ,l_qfros_snow(i)        ,fsno(i)              ,&
            rsur(i)              ,rnof(i)              ,qinfl(i)             ,d_pondmx            ,&
            d_ssi               ,d_wimp              ,d_smpmin            ,zwt(i)               ,&
            wa(i)                ,qcharge(i)           ,&
! SNICAR model variables
            l_forc_aer (:,i)          ,&
            mss_bcpho(t_lbsn:0,i) ,mss_bcphi(t_lbsn:0,i) ,mss_ocpho(t_lbsn:0,i) ,mss_ocphi(t_lbsn:0,i) ,&
            mss_dst1(t_lbsn:0,i)  ,mss_dst2(t_lbsn:0,i)  ,mss_dst3(t_lbsn:0,i)  ,mss_dst4(t_lbsn:0,i)  ,&
            vic_b_infilt(i)      ,vic_Dsmax(i)         ,vic_Ds(i)            ,vic_Ws(i)            ,&
            vic_c(i)             ,fevpg(i)                                                    )
   ELSE
!       CALL WATER_VSF (ipatch ,patchtype,is_dry_lake,   lb          ,nl_soil           ,&
!             deltim            ,z_soisno(lb:)     ,dz_soisno(lb:)    ,zi_soisno(lb-1:)  ,&
!             bsw               ,theta_r           ,fsatmax           ,fsatdcf           ,&
!             topostd           ,BVIC              ,&
!             porsl             ,psi0              ,hksati            ,rootr             ,&
!             rootflux          ,t_soisno(lb:)     ,wliq_soisno(lb:)  ,wice_soisno(lb:)  ,&
!             smp               ,hk                ,pg_rain           ,sm                ,&
!             etr               ,qseva             ,qsdew             ,qsubl             ,&
!             qfros             ,qseva_soil        ,qsdew_soil        ,qsubl_soil        ,&
!             qfros_soil        ,qseva_snow        ,qsdew_snow        ,qsubl_snow        ,&
!             qfros_snow        ,fsno              ,rsur              ,rsur_se           ,&
!             rsur_ie           ,rnof              ,qinfl             ,ssi               ,&
!             pondmx            ,wimp              ,zwt               ,wdsrf             ,&
!             wa                ,wetwat            ,&
! ! SNICAR model variables
!             forc_aer          ,&
!             mss_bcpho(lbsn:0) ,mss_bcphi(lbsn:0) ,mss_ocpho(lbsn:0) ,mss_ocphi(lbsn:0) ,&
!             mss_dst1(lbsn:0)  ,mss_dst2(lbsn:0)  ,mss_dst3(lbsn:0)  ,mss_dst4(lbsn:0)   )
   ENDIF

   IF (t_snl < 0) THEN
      ! Compaction rate for snow
      ! Natural compaction and metamorphosis. The compaction rate
      ! is recalculated for every new timestep
      t_lb  = t_snl + 1   !lower bound of array
      CALL snowcompaction (t_lb,l_deltim_phy(i),&
                        t_imelt(t_lb:0),l_fiold(t_lb:0,i),t_soisno(t_lb:0,i),&
                        wliq_soisno(t_lb:0,i),wice_soisno(t_lb:0,i),forc_us(i),forc_vs(i),l_dz_soisno(t_lb:0,i))
      ! Combine thin snow elements
      t_lb = maxsnl + 1
      IF (d_DEF_USE_SNICAR) THEN
         ! CALL snowlayerscombine_snicar (t_lb,t_snl,&
         !                z_soisno(t_lb:1),dz_soisno(t_lb:1),zi_soisno(t_lb-1:1),&
         !                wliq_soisno(t_lb:1),wice_soisno(t_lb:1),t_soisno(t_lb:1),scv,snowdp,&
         !                mss_bcpho(t_lb:0), mss_bcphi(t_lb:0), mss_ocpho(t_lb:0), mss_ocphi(t_lb:0),&
         !                mss_dst1(t_lb:0), mss_dst2(t_lb:0), mss_dst3(t_lb:0), mss_dst4(t_lb:0) )
      ELSE
         CALL snowlayerscombine (t_lb,t_snl,&
                        l_z_soisno(t_lb:1,i),l_dz_soisno(t_lb:1,i),l_zi_soisno(t_lb-1:1,i),&
                        wliq_soisno(t_lb:1,i),wice_soisno(t_lb:1,i),t_soisno(t_lb:1,i),scv(i),snowdp(i))
      ENDIF
      ! Divide thick snow elements
      IF(t_snl<0) THEN
         IF (d_DEF_USE_SNICAR) THEN
            ! CALL snowlayersdivide_snicar (t_lb,t_snl,&
            !             z_soisno(t_lb:0),dz_soisno(t_lb:0),zi_soisno(t_lb-1:0),&
            !             wliq_soisno(t_lb:0),wice_soisno(t_lb:0),t_soisno(t_lb:0),&
            !             mss_bcpho(t_lb:0),mss_bcphi(t_lb:0),mss_ocpho(t_lb:0),mss_ocphi(t_lb:0),&
            !             mss_dst1(t_lb:0),mss_dst2(t_lb:0),mss_dst3(t_lb:0),mss_dst4(t_lb:0) )
         ELSE
            CALL snowlayersdivide (t_lb,t_snl,&
                        l_z_soisno(t_lb:0,i),l_dz_soisno(t_lb:0,i),l_zi_soisno(t_lb-1:0,i),&
                        wliq_soisno(t_lb:0,i),wice_soisno(t_lb:0,i),t_soisno(t_lb:0,i))
         ENDIF
      ENDIF
   ENDIF
   ! Set zero to the empty node
   IF (t_snl > maxsnl) THEN
      wice_soisno(maxsnl+1:t_snl,i) = 0.
      wliq_soisno(maxsnl+1:t_snl,i) = 0.
      t_soisno   (maxsnl+1:t_snl,i) = 0.
      l_z_soisno   (maxsnl+1:t_snl,i) = 0.
      l_dz_soisno  (maxsnl+1:t_snl,i) = 0.
   ENDIF
   t_lb = t_snl + 1
   t_grnd(i) = t_soisno(t_lb,i)
   IF (l_is_dry_lake(i) == 1) THEN
      dz_lake(:,i) = wdsrf(i)*1.e-3/nl_lake
      t_lake(:,i)  = t_soisno(1,i)
      IF (t_soisno(1,i) >= tfrz) THEN
         lake_icefrac(:,i) = 0.
      ELSE
         lake_icefrac(:,i) = 1.
      ENDIF
      IF (wdsrf(i) >= 100.) THEN
         CALL adjust_lake_layer (nl_lake, dz_lake(:,i), t_lake(:,i), lake_icefrac(:,i))
      ENDIF
   ENDIF
   ! ----------------------------------------
   ! energy balance
   ! ----------------------------------------
   zerr(i)=l_errore(i)
   ! ----------------------------------------
   ! water balance
   ! ----------------------------------------
   l_endwb(i)=sum(wice_soisno(1:,i)+wliq_soisno(1:,i))+ldew(i)+scv(i) + wa(i)
   IF (d_DEF_USE_VariablySaturatedFlow) THEN
      l_endwb(i) = l_endwb(i) + wdsrf(i)
      IF (patchtype(i) == 2) THEN
         l_endwb(i) = l_endwb(i) + wetwat(i)
      ENDIF
   ENDIF
   l_errorw(i)=(l_endwb(i)-l_totwb(i))-(forc_prc(i)+forc_prl(i)-fevpa(i)-rnof(i))*l_deltim_phy(i)
   IF (.not. d_DEF_USE_VariablySaturatedFlow) THEN
      IF (patchtype(i)==2) l_errorw(i)=0.    !wetland
   ENDIF
   xerr(i)=l_errorw(i)/l_deltim_phy(i)

   l_snl(i) = t_snl
   l_imelt(:,i) = t_imelt(:)
END SUBROUTINE CoLMMAIN_Water_CUDA

attributes(global) SUBROUTINE CoLMMAIN_WaterBodies_CUDA ()

   USE cudafor
   USE MOD_ConstVars_CUDA
   USE MOD_AllocatableVars_CUDA

   USE MOD_Lake_CUDA

   IMPLICIT NONE

   real(r8) :: a, aa, sum_value
   integer  :: i, j, m
   integer  :: t_snl                      ,&! number of snow layers
               t_imelt(maxsnl+1:nl_soil)  ,&! flag for: melting=1, freezing=2, Nothing happened=0
               t_lb ,t_lbsn                 ! lower bound of arrays

   i = threadIdx%x + (blockIdx%x - 1) * blockDim%x
   if (i > d_numpatch) then
      return
   endif
   if (l_run_mask(i) /= 1) then
      return
   endif
   m = patchclass(i)

!======================================================================
   IF (patchtype(i) /= 4) THEN   ! <=== is LAND WATER BODIES (lake, reservoir and river) (patchtype = 4)
      return
   ENDIF

   t_snl = l_snl(i)
   t_imelt(:) = l_imelt(:,i)

   ! l_totwb(i) = scv(i) + sum(wice_soisno(1:,i)+wliq_soisno(1:,i)) + wa(i)
   sum_value = 0.
   DO j = 1, nl_soil
      sum_value = sum_value + wice_soisno(j,i) + wliq_soisno(j,i)
   ENDDO
   l_totwb(i) = scv(i) + sum_value + wa(i)

   IF (d_DEF_USE_Dynamic_Lake) THEN
      l_totwb(i) = l_totwb(i) + wdsrf(i)
   ENDIF
   t_snl = 0
   DO j = maxsnl+1, 0
      IF (wliq_soisno(j,i)+wice_soisno(j,i) > 0.) THEN
         t_snl=t_snl-1
      ENDIF
   ENDDO
   l_zi_soisno(0,i) = 0.
   IF (t_snl < 0) THEN
      DO j = -1, t_snl, -1
         l_zi_soisno(j,i)=l_zi_soisno(j+1,i)-l_dz_soisno(j+1,i)
      ENDDO
   ENDIF
   DO j = 1,nl_soil
      l_zi_soisno(j,i)=l_zi_soisno(j-1,i)+l_dz_soisno(j,i)
   ENDDO
   l_scvold(i) = scv(i)          !snow mass at previous time step
   l_fiold(:,i) = 0.0
   IF (t_snl < 0) THEN
      l_fiold(t_snl+1:0,i)=wice_soisno(t_snl+1:0,i)/(wliq_soisno(t_snl+1:0,i)+wice_soisno(t_snl+1:0,i))
   ENDIF

   ! l_w_old(i) = sum(wliq_soisno(1:,i)) + sum(wice_soisno(1:,i))
   sum_value = 0.
   DO j = 1, nl_soil
      sum_value = sum_value + wliq_soisno(j,i) + wice_soisno(j,i)
   ENDDO
   l_w_old(i) = 0.

   l_pg_rain(i) = l_prc_rain(i) + l_prl_rain(i)
   l_pg_snow(i) = l_prc_snow(i) + l_prl_snow(i)
   CALL newsnow_lake ( d_DEF_USE_Dynamic_Lake, &
         ! "in" arguments
         ! ---------------
         maxsnl       ,nl_lake      ,l_deltim_phy(i) ,dz_lake(:,i)         ,&
         l_pg_rain(i) ,l_pg_snow(i) ,l_t_precip(i)   ,l_bifall(i)          ,&
         ! "inout" arguments
         ! ------------------
         t_lake(:,i)  ,l_zi_soisno(:0,i),l_z_soisno(:0,i)    ,&
         l_dz_soisno(:0,i),t_soisno(:0,i) ,wliq_soisno(:0,i) ,wice_soisno(:0,i) ,&
         l_fiold(:0,i)    ,t_snl          ,sag(i)             ,scv(i)             ,&
         snowdp(i)       ,lake_icefrac(:,i))
   CALL laketem ( &
         ! "in" laketem arguments
         ! ---------------------------
         patchtype(i)      ,maxsnl            ,nl_soil              ,nl_lake              ,&
         patchlatr(i)      ,l_deltim_phy(i)   ,forc_hgt_u(i)        ,forc_hgt_t(i)        ,&
         forc_hgt_q(i)     ,forc_us(i)        ,forc_vs(i)           ,forc_t(i)            ,&
         forc_q(i)         ,forc_rhoair(i)    ,forc_psrf(i)         ,forc_sols(i)         ,&
         forc_soll(i)      ,forc_solsd(i)     ,forc_solld(i)        ,sabg(i)              ,&
         forc_frl(i)       ,l_dz_soisno(:,i)  ,l_z_soisno(:,i)      ,l_zi_soisno(:,i)     ,&
         dz_lake(:,i)      ,lakedepth(i)      ,vf_quartz(:,i)       ,vf_gravels(:,i)      ,&
         vf_om(:,i)        ,vf_sand(:,i)      ,wf_gravels(:,i)      ,wf_sand(:,i)         ,&
         porsl(:,i)        ,csol(:,i)         ,k_solids(:,i)        ,&
         dksatu(:,i)       ,dksatf(:,i)       ,dkdry(:,i)           ,&
         BA_alpha(:,i)     ,BA_beta(:,i)      ,forc_hpbl(i)         ,&
         ! "inout" laketem arguments
         ! ---------------------------
         t_grnd(i)         ,scv(i)            ,snowdp(i)            ,t_soisno(:,i)        ,&
         wliq_soisno(:,i)  ,wice_soisno(:,i)  ,t_imelt(:)           ,t_lake(:,i)          ,&
         lake_icefrac(:,i) ,savedtke1(i)      ,&
! SNICAR model variables
         l_snofrz(:,i)     ,l_sabg_snow_lyr(:,i),&
! END SNICAR model variables
         ! "out" laketem arguments
         ! ---------------------------
         taux(i)           ,tauy(i)           ,fsena(i)             ,&
         fevpa(i)          ,lfevpa(i)         ,fseng(i)             ,fevpg(i)             ,&
         l_qseva(i)        ,l_qsubl(i)        ,l_qsdew(i)           ,l_qfros(i)           ,&
         olrg(i)           ,fgrnd(i)          ,tref(i)              ,qref(i)              ,&
         trad(i)           ,emis(i)           ,z0m(i)               ,zol(i)               ,&
         rib(i)            ,ustar(i)          ,qstar(i)             ,tstar(i)             ,&
         fm(i)             ,fh(i)             ,fq(i)                ,l_sm(i)               )
   CALL snowwater_lake ( d_DEF_USE_Dynamic_Lake, &
         ! "in" snowater_lake arguments
         ! ---------------------------
         maxsnl            ,nl_soil           ,nl_lake              ,l_deltim_phy(i)      ,&
         d_ssi             ,d_wimp            ,porsl(:,i)           ,l_pg_rain(i)         ,&
         l_pg_snow(i)      ,dz_lake(:,i)      ,t_imelt(:0)          ,l_fiold(:0,i)        ,&
         l_qseva(i)        ,l_qsubl(i)        ,l_qsdew(i)           ,l_qfros(i)           ,&
         ! "inout" snowater_lake arguments
         ! ---------------------------
         l_dz_soisno(:,i)  ,l_dz_soisno(:,i)  ,l_zi_soisno(:,i)     ,t_soisno(:,i)        ,&
         wice_soisno(:,i)  ,wliq_soisno(:,i)  ,t_lake(:,i)          ,lake_icefrac(:,i)    ,&
         l_gwat(i)         ,&
         fseng(i)          ,fgrnd(i)          ,t_snl                ,scv(i)               ,&
         snowdp(i)         ,l_sm(i)           ,forc_us(i)           ,forc_vs(i)           ,&
! SNICAR model variables
         l_forc_aer(:,i)   ,&
         mss_bcpho(:,i)    ,mss_bcphi(:,i)    ,mss_ocpho(:,i)       ,mss_ocphi(:,i)       ,&
         mss_dst1(:,i)     ,mss_dst2(:,i)     ,mss_dst3(:,i)        ,mss_dst4(:,i)         )
   IF (.not. d_DEF_USE_Dynamic_Lake) THEN
      ! We assume the land water bodies have zero extra liquid water capacity
      ! (i.e.,constant capacity), all excess liquid water are put into the runoff,
      ! this unreasonable assumption should be updated in the future version

      ! a = (sum(wliq_soisno(1:,i))+sum(wice_soisno(1:,i))+scv(i)-l_w_old(i)-l_scvold(i))/l_deltim_phy(i)
      sum_value = 0.
      DO j = 1, nl_soil
         sum_value = sum_value + wliq_soisno(j,i) + wice_soisno(j,i)
      ENDDO
      a = (sum_value+scv(i)-l_w_old(i)-l_scvold(i))/l_deltim_phy(i)

      aa = l_qseva(i)+l_qsubl(i)-l_qsdew(i)-l_qfros(i)
      rsur(i) = max(0., l_pg_rain(i) + l_pg_snow(i) - aa - a)
      rnof(i) = rsur(i)
   ELSE
      ! wdsrf = sum(dz_lake) * 1.e3
      ! IF (wdsrf > lakedepth*1.e3) THEN
      !    rsur  = (wdsrf - lakedepth*1.e3) / deltim
      !    wdsrf = lakedepth*1.e3
      !    dz_lake = dz_lake * lakedepth/sum(dz_lake)
      !    CALL adjust_lake_layer (nl_lake, dz_lake, t_lake, lake_icefrac)
      ! ELSE
      !    rsur = 0.
      ! ENDIF
      ! rnof = rsur
      ! rsur_se = rsur
      ! rsur_ie = 0.
   ENDIF

   ! l_endwb(i)  = scv(i) + sum(wice_soisno(1:)+wliq_soisno(1:)) + wa
   sum_value = 0.
   DO j = 1, nl_soil
      sum_value = sum_value + wliq_soisno(j,i) + wice_soisno(j,i)
   ENDDO
   l_endwb(i)  = scv(i) + sum_value + wa(i)

   IF (d_DEF_USE_Dynamic_Lake) THEN
      l_endwb(i)  = l_endwb(i)  + wdsrf(i)
   ENDIF
   l_errorw(i) = (l_endwb(i)-l_totwb(i)) - (forc_prc(i)+forc_prl(i)-fevpa(i)) * l_deltim_phy(i)
   l_errorw(i) = l_errorw(i) + rnof(i) * l_deltim_phy(i)
   IF (d_DEF_USE_Dynamic_Lake) THEN
      xerr(i) = l_errorw(i) / l_deltim_phy(i)
   ELSE
      xerr(i) = 0.
   ENDIF
   ! Set zero to the empty node
   IF (t_snl > maxsnl) THEN
      wice_soisno(maxsnl+1:t_snl,i) = 0.
      wliq_soisno(maxsnl+1:t_snl,i) = 0.
      t_soisno   (maxsnl+1:t_snl,i) = 0.
      l_z_soisno (maxsnl+1:t_snl,i) = 0.
      l_dz_soisno(maxsnl+1:t_snl,i) = 0.
   ENDIF

   l_snl(i) = t_snl
END SUBROUTINE CoLMMAIN_WaterBodies_CUDA

attributes(global) SUBROUTINE CoLMMAIN_Preparation_CUDA ()

   USE cudafor
   USE MOD_Init_CUDA
   USE MOD_ConstVars_CUDA
   USE MOD_AllocatableVars_CUDA

   USE MOD_OrbCoszen_CUDA
   USE MOD_SnowFraction_CUDA
   USE MOD_Albedo_CUDA

   IMPLICIT NONE

   real(r8) t_soisno_    (maxsnl+1:1)  !soil + snow layer temperature [K]
   real(r8) dz_soisno_   (maxsnl+1:1)  !layer thickness (m)

   real(r8) :: ssw
   integer  :: i, j, m
   integer  :: t_snl

   i = threadIdx%x + (blockIdx%x - 1) * blockDim%x
   if (i > d_numpatch) then
      return
   endif
   if (l_run_mask(i) /= 1) then
      return
   endif
   m = patchclass(i)

   t_snl = l_snl(i)

! Preparation for the next time step
! 1) time-varying parameters for vegetation
! 2) fraction of snow cover
! 3) solar zenith angle and
! 4) albedos
!======================================================================
      ! cosine of solar zenith angle
      l_calday(i) = calendarday_cuda(d_idate)
      coszen(i) = orb_coszen(l_calday(i),patchlonr(i),patchlatr(i))

      IF (patchtype(i) <= 5) THEN   !LAND
! only for soil patches
!NOTE: lai from remote sensing has already considered snow coverage
!NOTE: IF account for snow on vegetation:
!        1) should use snow-free LAI data and 2) update LAI and SAI according to snowdp
         IF (patchtype(i) == 0) THEN
            CALL snowfraction (tlai(i),tsai(i),z0m(i),d_zlnd,scv(i),snowdp(i),l_wt(i),sigf(i),fsno(i))
            lai(i) = tlai(i)
            sai(i) = tsai(i) * sigf(i)
            !NOTE: use snow-free LAI by defining namelist DEF_VEG_SNOW
            IF ( d_DEF_VEG_SNOW ) THEN
               lai(i) = tlai(i) * sigf(i)
            ENDIF
         ELSE
            CALL snowfraction (tlai(i),tsai(i),z0m(i),d_zlnd,scv(i),snowdp(i),l_wt(i),sigf(i),fsno(i))
            lai(i) = tlai(i)
            sai(i) = tsai(i) * sigf(i)
            !NOTE: use snow-free LAI by defining namelist DEF_VEG_SNOW
            IF ( d_DEF_VEG_SNOW ) THEN
               lai(i) = tlai(i) * sigf(i)
            ENDIF
         ENDIF
         ! water volumetric content of soil surface layer [m3/m3]
         ssw = min(1.,1.e-3*wliq_soisno(1,i)/l_dz_soisno(1,i))
         IF (patchtype(i) >= 3) ssw = 1.0
! ============================================================================
! Snow aging routine based on Flanner and Zender (2006), Linking snowpack
! microphysics and albedo evolution, JGR, and Brun (1989), Investigation of
! wet-snow metamorphism in respect of liquid-water content, Ann. Glacial.
         dz_soisno_(:1) = l_dz_soisno(:1,i)
         t_soisno_ (:1) = t_soisno (:1,i)
         IF ((patchtype(i) == 4) .and. (l_is_dry_lake(i) == 0)) THEN
            dz_soisno_(1) = dz_lake(1,i)
            t_soisno_ (1) = t_lake (1,i)
         ENDIF
! ============================================================================
         ! albedos
         ! we supposed CALL it every time-step, because
         ! other vegetation related parameters are needed to create
         IF (d_doalb) THEN
            CALL albland (i,patchtype(i),l_deltim_phy(i),&
                 soil_s_v_alb(i),soil_d_v_alb(i),soil_s_n_alb(i),soil_d_n_alb(i),&
                 d_chil(m),d_rho(1:,1:,m),d_tau(1:,1:,m),fveg(i),green(i),lai(i),sai(i),fwet_snow(i),coszen(i),&
                 l_wt(i),fsno(i),scv(i),l_scvold(i),sag(i),ssw,l_pg_snow(i),forc_t(i),t_grnd(i),t_soisno_,dz_soisno_,&
                 t_snl,wliq_soisno(:,i),wice_soisno(:,i),snw_rds(:,i),l_snofrz(:,i),&
                 mss_bcpho(:,i),mss_bcphi(:,i),mss_ocpho(:,i),mss_ocphi(:,i),&
                 mss_dst1(:,i),mss_dst2(:,i),mss_dst3(:,i),mss_dst4(:,i),&
                 alb(:,:,i),ssun(:,:,i),ssha(:,:,i),ssoi(:,:,i),ssno(:,:,i),ssno_lyr(:,:,:,i),thermk(i),extkb(i),extkd(i))
         ENDIF
      ELSE                   !OCEAN
         sag(i) = 0.0
         IF(d_doalb)THEN
            CALL albocean (l_oro(i),scv(i),coszen(i),alb(:,:,i))
         ENDIF
      ENDIF
      ! zero-filling set for glacier/ice-sheet/land water bodies/ocean components
      IF ((patchtype(i) > 2) .and. (l_is_dry_lake(i) == 0)) THEN
         lai(i)           = 0.0
         sai(i)           = 0.0
         laisun(i)        = 0.0
         laisha(i)        = 0.0
         green(i)         = 0.0
         fveg(i)          = 0.0
         sigf(i)          = 0.0
         ssun(:,:,i)      = 0.0
         ssha(:,:,i)      = 0.0
         thermk(i)        = 0.0
         extkb(i)         = 0.0
         extkd(i)         = 0.0
         tleaf(i)         = forc_t(i)
         ldew_rain(i)     = 0.0
         ldew_snow(i)     = 0.0
         fwet_snow(i)     = 0.0
         ldew(i)          = 0.0
         fsenl(i)         = 0.0
         fevpl(i)         = 0.0
         etr(i)           = 0.0
         assim(i)         = 0.0
         respc(i)         = 0.0
         zerr(i)          = 0.
         qinfl(i)         = 0.
         qdrip(i)         = forc_rain(i) + forc_snow(i)
         qintr(i)         = 0.
         h2osoi(:,i)      = 0.
         rstfacsun_out(i) = 0.
         rstfacsha_out(i) = 0.
         gssun_out(i)     = 0.
         gssha_out(i)     = 0.
         assimsun_out(i)  = 0.
         etrsun_out(i)    = 0.
         assimsha_out(i)  = 0.
         etrsha_out(i)    = 0.
         rootr(:,i)       = 0.
         rootflux(:,i)    = 0.
         zwt(i)           = 0.
         IF (.not. d_DEF_USE_VariablySaturatedFlow) THEN
            wa(i) = 4800.
         ENDIF
         qcharge(i) = 0.
         IF (d_DEF_USE_PLANTHYDRAULICS)THEN
            vegwp(:,i) = -2.5e4
         ENDIF
      ENDIF
      h2osoi(:,i) = wliq_soisno(1:,i)/(l_dz_soisno(1:,i)*denh2o) + wice_soisno(1:,i)/(l_dz_soisno(1:,i)*denice)
      IF (d_DEF_USE_VariablySaturatedFlow) THEN
         wat(i) = sum(wice_soisno(1:,i)+wliq_soisno(1:,i))+ldew(i)+scv(i)+wetwat(i)
      ELSE
         wat(i) = sum(wice_soisno(1:,i)+wliq_soisno(1:,i))+ldew(i)+scv(i) + wa(i)
      ENDIF
      z_sno (maxsnl+1:0,i) = l_z_soisno (maxsnl+1:0,i)
      dz_sno(maxsnl+1:0,i) = l_dz_soisno(maxsnl+1:0,i)
END SUBROUTINE CoLMMAIN_Preparation_CUDA
! ---------- EOP ------------
