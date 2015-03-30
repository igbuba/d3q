!
! Written by Lorenzo Paulatto (2014-2015) IMPMC @ UPMC / CNRS UMR7590
!  released under the CeCILL licence v 2.1
!  <http://www.cecill.info/licences/Licence_CeCILL_V2.1-fr.txt>
!
MODULE final_state
  USE kinds,     ONLY : DP
  USE input_fc,  ONLY : ph_system_info, forceconst2_grid
  USE fc2_interpolate, ONLY : ip_cart2pat
  USE fc3_interpolate, ONLY : forceconst3
  !
  CONTAINS
  ! <<^V^\\=========================================//-//-//========//O\\//
  ! Full spectral function, computed as in eq. 1 of arXiv:1312.7467v1
  FUNCTION final_state_q(xq0, qpath, nconf, T, sigma, S, grid, fc2, fc3,&
                         ei, ne, ener, qresolved, sigmaq, outdir, prefix)
    USE fc2_interpolate,     ONLY : bose_phq, freq_phq_safe
    USE linewidth,      ONLY : sum_selfnrg_modes
    USE q_grids,        ONLY : q_grid
    USE functions,      ONLY : refold_bz, refold_bz_mod, f_gauss
    USE constants,      ONLY : RY_TO_CMM1
    USE more_constants, ONLY : write_conf
    !
    IMPLICIT NONE
    !
    REAL(DP),INTENT(in) :: xq0(3)
    TYPE(q_grid),INTENT(in) :: qpath
    INTEGER,INTENT(in)  :: nconf
    REAL(DP),INTENT(in) :: T(nconf)     ! Kelvin
    !
    REAL(DP),INTENT(in) :: ei       ! energy to examine (cm^-1)
    !
    INTEGER,INTENT(in)  :: ne       ! number of final state energies
    REAL(DP),INTENT(in) :: ener(ne) ! the final state energies
    REAL(DP),INTENT(in) :: sigmaq ! gaussian width used to select the q points
    LOGICAL,INTENT(in) :: qresolved
    CHARACTER(len=256),INTENT(in) :: outdir, prefix
    !
    TYPE(forceconst2_grid),INTENT(in) :: fc2
    CLASS(forceconst3),INTENT(in)     :: fc3
    TYPE(ph_system_info),INTENT(in)   :: S
    TYPE(q_grid),INTENT(in)      :: grid
    REAL(DP),INTENT(in) :: sigma(nconf) ! ry
    ! FUNCTION RESULT:
    REAL(DP) :: final_state_q(ne,S%nat3,nconf)
    !
    INTEGER :: unit
    INTEGER, EXTERNAL :: find_free_unit
    ! To interpolate D2 and D3:
    INTEGER :: iq, jq, nu, it
    COMPLEX(DP),ALLOCATABLE :: U(:,:,:), D3(:,:,:)
    REAL(DP),ALLOCATABLE    :: V3sq(:,:,:)
    REAL(DP) :: freq(S%nat3,3), bose(S%nat3,3), xq(3,3)
    !
    ! To compute the spectral function from the self energy:
    INTEGER  :: i, ie
    REAL(DP) :: gamma, delta, omega, denom
    COMPLEX(DP),ALLOCATABLE :: fstate_q(:,:,:)
    !
    REAL(DP) :: sumaux(ne,S%nat3)
    INTEGER     :: iqpath
    REAL(DP),ALLOCATABLE    :: xqbar(:,:,:,:)
    REAL(DP) :: qbarweight
    REAL(DP) :: pl,dpl
    !
    ALLOCATE(U(S%nat3, S%nat3,3))
    ALLOCATE(V3sq(S%nat3, S%nat3, S%nat3))
    ALLOCATE(D3(S%nat3, S%nat3, S%nat3))
    ALLOCATE(fstate_q(ne,S%nat3,nconf))
    !
    fstate_q = (0._dp, 0._dp)
    !
    IF(qresolved)THEN
      WRITE(*,'(2x,a,3f10.4,a,f12.6)') "Q-resolved final state", xq0, " energy = ", ei*RY_TO_CMM1
      ALLOCATE(xqbar(ne,S%nat3,qpath%nq,nconf))
    ENDIF
    !
    ! Compute eigenvalues, eigenmodes and bose-einstein occupation at q1
    xq(:,1) = xq0
    CALL freq_phq_safe(xq(:,1), S, fc2, freq(:,1), U(:,:,1))
    !
    DO iq = 1, grid%nq
      !
      xq(:,2) = grid%xq(:,iq)
      xq(:,3) = -(xq(:,2)+xq(:,1))
!/nope/!$OMP PARALLEL DO DEFAULT(shared) PRIVATE(jq)
      DO jq = 2,3
        CALL freq_phq_safe(xq(:,jq), S, fc2, freq(:,jq), U(:,:,jq))
      ENDDO
!/nope/!$OMP END PARALLEL DO
      !
      ! ------ start of CALL scatter_3q(S,fc2,fc3, xq(:,1),xq(:,2),xq(:,3), V3sq)
      CALL fc3%interpolate(xq(:,2), xq(:,3), S%nat3, D3)
      CALL ip_cart2pat(D3, S%nat3, U(:,:,1), U(:,:,2), U(:,:,3))
      V3sq = REAL( CONJG(D3)*D3 , kind=DP)
      !
      DO it = 1,nconf
        ! Compute eigenvalues, eigenmodes and bose-einstein occupation at q2 and q3
!/nope/!$OMP PARALLEL DO DEFAULT(shared) PRIVATE(jq)
        DO jq = 1,3
          CALL bose_phq(T(it),s%nat3, freq(:,jq), bose(:,jq))
        ENDDO
!/nope/!$OMP END PARALLEL DO
        sumaux = sum_final_state_e( S, sigma(it), freq, bose, V3sq, ei, ne, ener )
!         sumaux = sum_final_state_e( S, sigma(:,it), freq, bose, V3sq, freq(6,1), ne, ener )
        fstate_q(:,:,it) = fstate_q(:,:,it) + sumaux
        !
        IF(qresolved) THEN
!           sumaux = sum_selfnrg_modes( S, sigma(it), freq, bose, V3sq)
          DO iqpath = 1,qpath%nq
            !qbarweight = f_gauss(refold_bz_mod(qpath%xq(:,iqpath)-xq(:,2), S%bg), sigmaq)
            qbarweight = f_gauss(refold_bz_mod(qpath%xq(:,iqpath),S%bg) &
                                 -refold_bz_mod(xq(:,2), S%bg), sigmaq)
            xqbar(:,:,iqpath,it) = xqbar(:,:,iqpath,it) - 0.5_dp * sumaux *  qbarweight
          ENDDO
        ENDIF
        !
      ENDDO
      !
    ENDDO
    !
    IF(qresolved)THEN
      !
      unit = find_free_unit()
      DO it = 1,nconf
        OPEN(unit, file=TRIM(outdir)//"/"//TRIM(prefix)//&
                        ".q_resolved.T"//TRIM(write_conf(it,nconf,T))//&
                        "s"//TRIM(write_conf(it,nconf,sigma))//"out")
        pl = 0._dp; dpl = 0._dp
        DO iqpath = 1,qpath%nq
          IF(iqpath>1) dpl = SQRT(SUM( (qpath%xq(:,iqpath-1)-qpath%xq(:,iqpath))**2 ))
          pl = pl + dpl
          DO ie = 1,ne
            WRITE(unit,'(2f12.6,100e15.5)') ener(ie)*RY_TO_CMM1, &
                            pl, xqbar(ie,:,iqpath,it)
          ENDDO
          WRITE(unit,*) 
        ENDDO
        CLOSE(unit)
      ENDDO
      DEALLOCATE(xqbar)
    ENDIF
    !
    final_state_q = -0.5_dp * fstate_q/grid%nq
    !
    DEALLOCATE(U, V3sq, D3, fstate_q)
    !
  END FUNCTION final_state_q
  !
  ! Sum the self energy at the provided ener(ne) input energies
  ! \/o\________\\\_________________________________________/^>
  FUNCTION sum_final_state_e(S, sigma, freq, bose, V3sq, ei, ne, ener)
    USE functions, ONLY : f_gauss
    IMPLICIT NONE
    TYPE(ph_system_info),INTENT(in)   :: S
    REAL(DP),INTENT(in) :: sigma   ! smearing (regularization) (Ry)
    REAL(DP),INTENT(in) :: freq(S%nat3,3)  ! phonon energies (Ry)
    REAL(DP),INTENT(in) :: bose(S%nat3,3)  ! bose/einstein distribution of freq
    REAL(DP),INTENT(in) :: V3sq(S%nat3,S%nat3,S%nat3) ! |D^3|**2 on the basis of phonons patterns
    !
    REAL(DP),INTENT(in) :: ei ! the energy of the state under scrutiny
    !
    INTEGER,INTENT(in)  :: ne           ! number of energies on which to decompose the final state
    REAL(DP),INTENT(in) :: ener(ne)     ! the energies
    REAL(DP)            :: de
    !
    ! _P -> scattering, _M -> cohalescence
    REAL(DP) :: bose_P, bose_M      ! final/initial state populations 
    REAL(DP) :: freqtot, freqtotm1
    REAL(DP) :: omega_P,  omega_M   ! \delta\omega
    REAL(DP) :: omega_P2, omega_M2  ! \delta\omega
    REAL(DP) :: wfinal(ne)
    COMPLEX(DP) :: ctm_P, ctm_M, reg, num
    !
    INTEGER :: i,j,k, ie
    !
    ! Note: using the function result in an OMP reduction causes crash with ifort 14
    REAL(DP) :: sum_final_state_e(ne,S%nat3)
    COMPLEX(DP),ALLOCATABLE :: fsdf(:,:) ! final state decay function
    !
    ALLOCATE(fsdf(ne,S%nat3))
    fsdf = (0._dp, 0._dp)
    !
    de = ABS(ener(2)-ener(ne))/100._dp ! FIXME
    !
    !
!$OMP PARALLEL DO DEFAULT(SHARED) &
!$OMP             PRIVATE(ie,i,j,k,bose_P,bose_M,omega_P,omega_M,omega_P2,omega_M2,&
!$OMP                     ctm_P,ctm_M,reg,freqtot,freqtotm1,wfinal) &
!$OMP             REDUCTION(+: fsdf) COLLAPSE(2)
    DO k = 1,S%nat3
      DO j = 1,S%nat3
        !
        FORALL(i=1:ne) wfinal(i) = f_gauss((ener(i)-freq(j,2)), de)
        !
        bose_P   = 1 + bose(j,2) + bose(k,3)
        omega_P  = freq(j,2)+freq(k,3)
        omega_P2 = omega_P**2
        !
        bose_M   = bose(k,3) - bose(j,2)
        omega_M  = freq(j,2)-freq(k,3)
        omega_M2 = omega_M**2
        !
        DO i = 1,S%nat3
!           i = 6
          !
          ! This comes from the definition of u_qj, Ref. 1. in linewidth.f90
          freqtot = 8*freq(i,1)*freq(j,2)*freq(k,3)
          !
          IF (freqtot/=0._dp) THEN
            freqtotm1 = 1 / freqtot
            !
            DO ie = 1, ne
            ! regularization:
              reg = CMPLX(ei, sigma, kind=DP)**2
              !
              ctm_P = 2 * bose_P *omega_P/(omega_P2-reg)
              ctm_M = 2 * bose_M *omega_M/(omega_M2-reg)
              !
              fsdf(ie,i) = fsdf(ie,i) + wfinal(ie)*(ctm_P + ctm_M) * V3sq(i,j,k) * freqtotm1
            ENDDO
          ENDIF
          !
        ENDDO
      ENDDO
    ENDDO
!$OMP END PARALLEL DO
    !
    sum_final_state_e = -DIMAG(fsdf)
    DEALLOCATE(fsdf)
    !
  END FUNCTION sum_final_state_e
  
END MODULE final_state 