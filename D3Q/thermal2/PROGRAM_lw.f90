!
! Written by Lorenzo Paulatto (2013-2016) IMPMC @ UPMC / CNRS UMR7590
!  Dual licenced under the CeCILL licence v 2.1
!  <http://www.cecill.info/licences/Licence_CeCILL_V2.1-fr.txt>
!  and under the GPLv2 licence and following, see
!  <http://www.gnu.org/copyleft/gpl.txt>
!
! CONVENTIONS :
! xR, xq --> cartesian coordinates
! yR, yq --> crystalline coordinates
!
!
!
MODULE linewidth_program
  USE timers
  !
  USE kinds,       ONLY : DP
  !USE mpi_thermal,      ONLY : ionode
#include "mpi_thermal.h"
  !
  CONTAINS
  ! Test subroutine: compute phonon frequencies along a line and save them to unit 666  
  SUBROUTINE LW_QBZ_LINE(input, qpath, S, fc2, fc3)
    USE fc2_interpolate,    ONLY : fftinterp_mat2, mat2_diag, freq_phq
    USE linewidth,          ONLY : linewidth_q, selfnrg_q, spectre_q
    USE constants,          ONLY : RY_TO_CMM1
    USE q_grids,            ONLY : q_grid, setup_grid
    USE more_constants,     ONLY : write_conf
    USE fc3_interpolate,    ONLY : forceconst3
    USE isotopes_linewidth, ONLY : isotopic_linewidth_q
    USE casimir_linewidth,  ONLY : casimir_linewidth_q
    USE input_fc,           ONLY : forceconst2_grid, ph_system_info
    USE code_input,         ONLY : code_input_type
    IMPLICIT NONE
    !
    TYPE(code_input_type),INTENT(in)     :: input
    TYPE(forceconst2_grid),INTENT(in) :: fc2
    CLASS(forceconst3),INTENT(in)     :: fc3
    TYPE(ph_system_info),INTENT(in)   :: S
    TYPE(q_grid),INTENT(in)      :: qpath
    !
    COMPLEX(DP) :: D(S%nat3, S%nat3)
    REAL(DP) :: w2(S%nat3)
    INTEGER :: iq, it
    TYPE(q_grid) :: grid
    COMPLEX(DP):: ls(S%nat3,input%nconf), lsx(S%nat3)
    REAL(DP)   :: lw(S%nat3,input%nconf)
    REAL(DP)   :: lw_casimir(S%nat3)
    REAL(DP)   :: sigma_ry(input%nconf)
    CHARACTER(len=15) :: f1, f2
    CHARACTER(len=256) :: filename
    ! RAFTEST
    INTEGER :: nu
    !
    CALL setup_grid(input%grid_type, S%bg, input%nk(1), input%nk(2), input%nk(3), grid, scatter=.true.)
    !CALL grid%scatter()
    !
    IF(ionode)THEN
    DO it = 1,input%nconf
      filename=TRIM(input%outdir)//"/"//&
               TRIM(input%prefix)//"_T"//TRIM(write_conf(it,input%nconf,input%T))//&
                 "_s"//TRIM(write_conf(it,input%nconf,input%sigma))//".out"
      OPEN(unit=1000+it, file=filename)
      IF (TRIM(input%mode) == "full") THEN
        ioWRITE(1000+it, *) "# calculation of linewidth (gamma_n) [and lineshift (delta_n)]"
      ELSE
        ioWRITE(1000+it, *) "# calculation of linewidth (gamma_n)"
      ENDIF
      ioWRITE(1000+it, '(a,i6,a,f6.1,a,100f6.1)') "# ", it, "     T=",input%T(it), "    sigma=", input%sigma(it)
      ioFLUSH(1000+it)
    ENDDO
    ! Prepare formats to write out data
    ioWRITE(f1,'(i6,a)') S%nat3, "f12.6,6x,"
    ioWRITE(f2,'(i6,a)') S%nat3, "e15.5,6x,"
    ENDIF
    !
    ! Gaussian: exp(x^2/(2s^2)) => FWHM = 2sqrt(2log(2)) s
    ! Wrong Gaussian exp(x^2/c^2) => FWHM = 2 sqrt(log(2)) c
    ! Lorentzian: (g/2)/(x^2 + (g/2)^2) => FWHM = g
    ! Wrong Lorentzian: d/(x^2+d^2) => FWHM = 2d
    !  => 2d = 2 sqrt(log(2) c
    !      d = sqrt(log(2)) c
    !      d = 0.83255 c
    ! IMHO: you need to use a sigma that is 0.6 (=0.5/0.83255) times smaller when using
    ! linewidth_q than when using selfnrg_q in order to get the same values
    ! THIS FACTOR IS NOW INCLUDED DIRECTLY IN SUM_LINEWIDTH_MODES!
    sigma_ry = input%sigma/RY_TO_CMM1
    !
    ioWRITE(*,'(2x,a,i6,a)') "Going to compute", qpath%nq, " points (1)"
    !
    DO iq = 1,qpath%nq
      ioWRITE(*,'(i6,3f15.8)') iq, qpath%xq(:,iq)
      !
      CALL freq_phq(qpath%xq(:,iq), S, fc2, w2, D)
      !
      IF (TRIM(input%mode) == "full") THEN
        ls = selfnrg_q(qpath%xq(:,iq), input%nconf, input%T, sigma_ry, &
                        S, grid, fc2, fc3)
        DO it = 1,input%nconf
          ! RAFTEST
          !DO nu=1,S%nat3
          !  write(*,*) 'AA', w2(nu)*RY_TO_CMM1, ls(nu,it)*RY_TO_CMM1, (w2(nu)+ls(nu,it))*RY_TO_CMM1
          !END DO
          lsx = ls(:,it)
          IF(input%sort_shifted_freq) THEN
            CALL resort_w_ls(S%nat3, w2, lsx)
          ELSE
            lsx = lsx + w2
          ENDIF
          ioWRITE(1000+it, '(i4,f12.6,2x,3f12.6,2x,'//f1//f2//f2//'x)') &
                iq,qpath%w(iq),qpath%xq(:,iq), w2*RY_TO_CMM1, -DIMAG(lsx)*RY_TO_CMM1, DBLE(lsx)*RY_TO_CMM1
          ioFLUSH(1000+it)
        ENDDO
      ELSE IF (TRIM(input%mode) == "real" .or. TRIM(input%mode) == "imag") THEN
          timer_CALL t_lwphph%start()
        lw = linewidth_q(qpath%xq(:,iq), input%nconf, input%T,  sigma_ry, &
                        S, grid, fc2, fc3)
          timer_CALL t_lwphph%stop()
        IF(input%isotopic_disorder)THEN
          timer_CALL t_lwisot%start()
        lw = lw + isotopic_linewidth_q(qpath%xq(:,iq), input%nconf, input%T,  sigma_ry, &
                                      S, grid, fc2)
          timer_CALL t_lwisot%stop()
        ENDIF
        IF(input%casimir_scattering)THEN
          timer_CALL t_lwcasi%start()
         lw_casimir = casimir_linewidth_q(qpath%xq(:,iq), input%casimir_length, &
                                      input%casimir_dir, S, fc2)
         DO it = 1,input%nconf
          lw(:,it) = lw(:,it) + lw_casimir
         ENDDO
          timer_CALL t_lwcasi%stop()
        ENDIF
        
        DO it = 1,input%nconf
          ioWRITE(1000+it, '(i4,f12.6,2x,3f12.6,2x,'//f1//f2//'x)') &
                iq,qpath%w(iq),qpath%xq(:,iq), w2*RY_TO_CMM1, lw(:,it)*RY_TO_CMM1
          ioFLUSH(1000+it)
        ENDDO
      ELSE
        CALL errore('LW_QBZ_LINE', 'wrong mode (imag or full)', 1)
      ENDIF
      !
    ENDDO
    !
    !
    IF(ionode)THEN
    DO it = 1,input%nconf
      CLOSE(unit=1000+it)
    ENDDO
    ENDIF
    !
#ifdef timer_CALL
      ioWRITE(stdout,'("   * WALL : ",f12.4," s")') get_wall()
      CALL print_timers_header()
      timer_CALL t_lwisot%print()
      timer_CALL t_lwcasi%print()
      timer_CALL t_lwphph%print()
      ioWRITE(*,'(a)') "*** * Contributions to ph-ph linewidth time:"
      timer_CALL t_freq%print() 
      timer_CALL t_bose%print() 
      timer_CALL t_sum%print() 
      timer_CALL t_fc3int%print() 
      timer_CALL t_fc3m2%print() 
      timer_CALL t_fc3rot%print() 
      timer_CALL t_mpicom%print() 
#endif
    !
  END SUBROUTINE LW_QBZ_LINE
  !
  ! Sort w and ls so that w+real(ls) is in increasing order
  ! On output, give ls+w correctly sorted, leave w unchanged
  SUBROUTINE resort_w_ls(nat3, w, ls)
    IMPLICIT NONE
    INTEGER,INTENT(in) :: nat3
    REAL(DP),INTENT(in) :: w(nat3)
    COMPLEX(DP),INTENT(inout):: ls(nat3)
    !
    REAL(DP)   :: wx(nat3)
    COMPLEX(DP):: lsx(nat3)
    REAL(DP)   :: tot(nat3), maxx, minx
    INTEGER    :: i,j
    ! Use stupid O(n^2) sort as quicksort with two list would be boring to implement
    tot = w + DBLE(ls)
    maxx = MAXVAL(tot)+1._dp
    DO i = 1, nat3
      minx = MINVAL(tot)
      j_LOOP : DO j = 1,nat3
        IF(tot(j)==minx)THEN
        !ioWRITE(*,'(a,2i3,4f12.6)') "min", i, j, minx, wx(i), DBLE(lsx(i)), tot(j)
         wx(i)  = w(j)
         lsx(i) = ls(j)
         tot(j) = maxx
         EXIT j_LOOP
        ENDIF
      ENDDO j_LOOP
    ENDDO
    !w  = wx
    ls = lsx+wx
  END SUBROUTINE
  !  
  SUBROUTINE SPECTR_QBZ_LINE(input, qpath, S, fc2, fc3)
    USE fc2_interpolate,     ONLY : fftinterp_mat2, mat2_diag, freq_phq
    USE linewidth,      ONLY : spectre_q, simple_spectre_q, add_exp_t_factor
    USE constants,      ONLY : RY_TO_CMM1
    USE q_grids,        ONLY : q_grid, setup_grid
    USE more_constants, ONLY : write_conf
    USE input_fc,       ONLY : forceconst2_grid, ph_system_info
    USE fc3_interpolate,ONLY : forceconst3
    USE code_input,     ONLY : code_input_type
    IMPLICIT NONE
    !
    TYPE(code_input_type),INTENT(in)     :: input
    TYPE(forceconst2_grid),INTENT(in) :: fc2
    CLASS(forceconst3),INTENT(inout)  :: fc3
    TYPE(ph_system_info),INTENT(in)   :: S
    TYPE(q_grid),INTENT(in)      :: qpath
    !
    INTEGER :: iq, it, ie
    TYPE(q_grid) :: grid
    COMPLEX(DP):: ls(S%nat3,input%nconf)
    REAL(DP)   :: sigma_ry(input%nconf)
    !
    REAL(DP),ALLOCATABLE :: ener(:), spectralf(:,:,:)
    !
    COMPLEX(DP) :: D(S%nat3, S%nat3)
    REAL(DP) :: w2(S%nat3)
    ALLOCATE(spectralf(input%ne,S%nat3,input%nconf))
    !
    CALL setup_grid(input%grid_type, S%bg, input%nk(1), input%nk(2), input%nk(3), grid, scatter=.true.)
    !CALL grid%scatter()
    !
    ALLOCATE(ener(input%ne))
    FORALL(ie = 1:input%ne) ener(ie) = (ie-1)*input%de+input%e0
    ener = ener/RY_TO_CMM1
    sigma_ry = input%sigma/RY_TO_CMM1
    !
    IF(ionode)THEN
    DO it = 1,input%nconf
      OPEN(unit=1000+it, file=TRIM(input%outdir)//"/"//&
                              TRIM(input%prefix)//"_T"//TRIM(write_conf(it,input%nconf,input%T))//&
                              "_s"//TRIM(write_conf(it,input%nconf,input%sigma))//".out")
      ioWRITE(1000+it, *) "# spectral function mode: ", input%mode
      ioWRITE(1000+it, '(a,i6,a,f6.1,a,100f6.1)') "#", it, "T=",input%T(it), "sigma=", input%sigma(it)
      ioWRITE(1000+it, *) "#   q-path     energy (cm^-1)         total      band1      band2    ....     "
      ioFLUSH(1000+it)
    ENDDO
    ENDIF
    !
    ioWRITE(*,'(2x,a,i6,a)') "Going to compute", qpath%nq, " points (2)"
    
    DO iq = 1,qpath%nq
      CALL freq_phq(qpath%xq(:,iq), S, fc2, w2, D)
      ioWRITE(*,'(i6,3f12.6,5x,6f12.6,100(/,47x,6f12.6))') iq, qpath%xq(:,iq), w2*RY_TO_CMM1
      !
      DO it = 1,input%nconf
        ioWRITE(1000+it, *)
        ioWRITE(1000+it, '(a,i6,3f15.8,5x,100(/,"#",6f12.6))') "#  xq",  iq, qpath%xq(:,iq), w2*RY_TO_CMM1
      ENDDO
      !
      IF (TRIM(input%mode) == "full") THEN
        spectralf = spectre_q(qpath%xq(:,iq), input%nconf, input%T, sigma_ry, &
                                  S, grid, fc2, fc3, input%ne, ener)
      ELSE IF (TRIM(input%mode) == "simple") THEN
        spectralf = simple_spectre_q(qpath%xq(:,iq), input%nconf, input%T, sigma_ry, &
                                  S, grid, fc2, fc3, input%ne, ener)
      ELSE
        CALL errore("SPECTR_QBZ_LINE", 'unknown mode "'//TRIM(input%mode)//'"', 1)
      ENDIF
      !
      IF(input%exp_t_factor) CALL add_exp_t_factor(input%nconf, input%T, input%ne, S%nat3, ener, spectralf)
      !RAF change of units, since now I multiplicate by omega
      DO it = 1,input%nconf
        DO ie = 1,input%ne
          !ioWRITE(1000+it, '(2f14.8,100e14.6)') &
          !        qpath%w(iq), ener(ie)*RY_TO_CMM1, SUM(spectralf(ie,:,it))/RY_TO_CMM1**2, spectralf(ie,:,it)/RY_TO_CMM1**2        
          ioWRITE(1000+it, '(2f14.8,100e14.6)') &
                qpath%w(iq), ener(ie)*RY_TO_CMM1, SUM(spectralf(ie,:,it))/RY_TO_CMM1, spectralf(ie,:,it)/RY_TO_CMM1
          ioFLUSH(1000+it)
        ENDDO
      ENDDO
      !
    ENDDO
    !
    !
    IF(ionode)THEN
    DO it = 1,input%nconf
      CLOSE(unit=1000+it)
    ENDDO
    ENDIF
    !
    DEALLOCATE(spectralf, ener)
    !
  END SUBROUTINE SPECTR_QBZ_LINE
  !   
  !  
  SUBROUTINE FINAL_STATE_LINE(input, qpath, S, fc2, fc3)
    USE fc2_interpolate,     ONLY : fftinterp_mat2, mat2_diag
    USE  final_state,   ONLY : final_state_q
    USE constants,      ONLY : RY_TO_CMM1
    USE q_grids,        ONLY : q_grid, setup_grid
    USE more_constants, ONLY : write_conf
    USE input_fc,       ONLY : forceconst2_grid, ph_system_info
    USE fc3_interpolate,ONLY : forceconst3
    USE code_input,     ONLY : code_input_type
    IMPLICIT NONE
    !
    TYPE(code_input_type),INTENT(in)     :: input
    TYPE(forceconst2_grid),INTENT(in) :: fc2
    CLASS(forceconst3),INTENT(inout)  :: fc3
    TYPE(ph_system_info),INTENT(in)   :: S
    TYPE(q_grid),INTENT(in)      :: qpath
    !
    REAL(DP) :: e_inital_ry 
    INTEGER :: iq, it, ie
    TYPE(q_grid) :: grid
    COMPLEX(DP):: ls(S%nat3,input%nconf)
    REAL(DP) :: sigma_ry(input%nconf)
    !
    REAL(DP),PARAMETER :: inv2_RY_TO_CMM1 = 1/(RY_TO_CMM1)**2
    !
    REAL(DP),ALLOCATABLE :: ener(:), fstate(:,:,:)
    CHARACTER(len=256) :: filename
    !
    ALLOCATE(fstate(input%ne,S%nat3,input%nconf))
    !
    CALL setup_grid(input%grid_type, S%bg, input%nk(1), input%nk(2), input%nk(3), grid, scatter=.true.)
    !CALL grid%scatter()
    !
    ALLOCATE(ener(input%ne))
    FORALL(ie = 1:input%ne) ener(ie) = (ie-1)*input%de+input%e0
    ! Convert to Rydberg:
    ener = ener/RY_TO_CMM1
    e_inital_ry = input%e_initial/RY_TO_CMM1
    sigma_ry = input%sigma/RY_TO_CMM1
    !
    IF(ionode)THEN 
    DO it = 1,input%nconf
      filename = TRIM(input%outdir)//"/"//&
                 TRIM(input%prefix)//"_T"//TRIM(write_conf(it,input%nconf,input%T))//&
                 "_s"//TRIM(write_conf(it,input%nconf,input%sigma))//".out"
      OPEN(unit=1000+it, file=filename)
      ioWRITE(*,*) "opening ", TRIM(filename)
      ioWRITE(1000+it, *) "# final state decompositions, mode: ", input%mode
      ioWRITE(1000+it, '(a,i6,a,f6.1,a,100f6.1)') "#", it, "T=",input%T(it), "sigma=", input%sigma(it)
      ioWRITE(1000+it, *) "# energy (cm^-1)         total      band1      band2    ....     "
      ioFLUSH(1000+it)
    ENDDO
    ENDIF
    !
    ioWRITE(*,'(2x,a,3f12.6,a,1f12.6,a)') "Going to compute final state decomposition for", &
                                input%q_initial, "  energy:", input%e_initial, "cm^-1"
    
    !DO iq = 1,qpath%nq
      !ioWRITE(*,'(i6,3f15.8)') iq, qpath%xq(:,iq)
      !
!       DO it = 1,input%nconf
!         ioWRITE(1000+it, *)
!         ioWRITE(1000+it, '(a,i6,3f15.8)') "#  xq",  iq, qpath%xq(:,iq)
!       ENDDO
      !
      fstate = final_state_q(input%q_initial, qpath, input%nconf, input%T, sigma_ry, &
                             S, grid, fc2, fc3, e_inital_ry, input%ne, ener, &
                             input%q_resolved, input%sigmaq, input%outdir, input%prefix)
      !
      DO it = 1,input%nconf
        DO ie = 1,input%ne
          ioWRITE(1000+it, '(1f14.8,100e18.6e3)') &
               ener(ie)*RY_TO_CMM1, SUM(fstate(ie,:,it)), fstate(ie,:,it)
          ioFLUSH(1000+it)
        ENDDO
      ENDDO
      !
    !ENDDO
    !
    !
    IF(ionode)THEN
    DO it = 1,input%nconf
      CLOSE(unit=1000+it)
    ENDDO
    ENDIF
    !
    DEALLOCATE(fstate, ener)
    !
  END SUBROUTINE FINAL_STATE_LINE
  !   
  END MODULE linewidth_program
!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!
!               !               !               !               !               !               !
!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!
PROGRAM linewidth

  USE kinds,            ONLY : DP
  USE linewidth_program
  USE input_fc,         ONLY : forceconst2_grid, ph_system_info
  USE q_grids,          ONLY : q_grid !, setup_grid
  USE fc3_interpolate,  ONLY : forceconst3
  USE code_input,       ONLY : READ_INPUT, code_input_type
  USE mpi_thermal,      ONLY : start_mpi, stop_mpi, ionode
  USE more_constants,   ONLY : print_citations_linewidth
  IMPLICIT NONE
  !
  TYPE(forceconst2_grid) :: fc2
  CLASS(forceconst3),POINTER :: fc3
  TYPE(ph_system_info)   :: S
  TYPE(code_input_type)     :: lwinput
  TYPE(q_grid)      :: qpath

!   CALL mp_world_start(world_comm)
!   CALL environment_start('LW')
  CALL start_mpi()
  CALL init_nanoclock()
  !
  IF(ionode) CALL print_citations_linewidth()

  ! READ_INPUT also reads force constants from disk, using subroutine READ_DATA
  CALL READ_INPUT("LW", lwinput, qpath, S, fc2, fc3)
  !
  IF(    TRIM(lwinput%calculation) == "lw"   &
    .or. TRIM(lwinput%calculation) == "grid" &
    ) THEN
    !
    CALL LW_QBZ_LINE(lwinput, qpath, S, fc2, fc3)
    !
  ELSE &
  IF(TRIM(lwinput%calculation) == "spf") THEN
    !
    CALL SPECTR_QBZ_LINE(lwinput, qpath, S, fc2, fc3)
    !
!   ELSE &
!   IF(TRIM(lwinput%calculation) == "grid") THEN
!     !
!     ! Compute the linewidth over the grid, will be reused later to do self-consistent linewidth
!     CALL LW_QBZ_LINE(lwinput, qpath, S, fc2, fc3)
  ELSE &
  IF(TRIM(lwinput%calculation) == "final") THEN
    !
    CALL FINAL_STATE_LINE(lwinput, qpath, S, fc2, fc3)
    !
  ELSE
    CALL errore("lw", "what else to do?", 1)
  ENDIF
  !
  IF(ionode) CALL print_citations_linewidth()
  CALL stop_mpi()
 
END PROGRAM
!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!

