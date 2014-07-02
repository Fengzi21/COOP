module coop_healpix_mod
!!I always assume ring order
  use coop_wrapper_utils
  use coop_sphere_mod
  use head_fits
  use fitstools
  use pix_tools
  use alm_tools
  implicit none

#include "constants.h"

  private

  public::coop_healpix_maps, coop_healpix_disc, coop_healpix_split,  coop_healpix_plot_spots,  coop_healpix_inpainting, coop_healpix_smooth_maskfile, coop_healpix_output_map, coop_healpix_get_disc, coop_healpix_stack_io, coop_healpix_export_spots, coop_healpix_smooth_mapfile


  integer,parameter::sp = kind(1.)
  integer,parameter::dl = kind(1.d0)
  integer,parameter::dlc = kind( (1.d0,1.d0) )
  integer,parameter::coop_inpainting_lowl_max = 20
  integer,parameter::coop_inpainting_lowl_min = 5
  real(dl),parameter::coop_healpix_inpaiting_lowpass_fwhm = 10.d0*coop_SI_degree

  integer, parameter::coop_healpix_default_lmax=2500
  integer, parameter::coop_healpix_mask_tol = 0.75
  integer::coop_healpix_inpainting_lowl=5

  integer,parameter::coop_healpix_index_TT = 1
  integer,parameter::coop_healpix_index_EE = 2
  integer,parameter::coop_healpix_index_BB = 3
  integer,parameter::coop_healpix_index_TE = 4
  integer,parameter::coop_healpix_index_EB = 5
  integer,parameter::coop_healpix_index_TB = 6

  type, extends(coop_sphere_disc):: coop_healpix_disc
     integer nside
     integer center
   contains
     procedure :: pix2ang => coop_healpix_disc_pix2ang
     procedure :: ang2pix => coop_healpix_disc_ang2pix
     procedure :: pix2xy => coop_healpix_disc_pix2xy
     procedure :: xy2pix => coop_healpix_disc_xy2pix
  end type coop_healpix_disc

  type coop_healpix_stacked_map
     integer n, n_threads
     real(sp) dr
     real(sp) zmax, zmin
     logical want_qu
     real(sp), dimension(:), allocatable::nstack
     real(sp), dimension(:,:,:), allocatable::image
     real(sp), dimension(:,:,:), allocatable::uimage

  end type coop_healpix_stacked_map

  type coop_healpix_maps
     integer npix, nside, nmaps, ordering, lmax, iq, iu, mask_npix, maskpol_npix
     character(LEN=80),dimension(64)::header
     integer,dimension(:),allocatable::spin
     real(sp), dimension(:,:),allocatable::map
     complex, dimension(:,:,:),allocatable::alm
     real(sp), dimension(:,:),allocatable::Cl
     integer,dimension(:),allocatable::mask_listpix, maskpol_listpix
     real(dl) chisq, mcmc_temperature
   contains
     procedure :: init => coop_healpix_maps_init
     procedure :: free => coop_healpix_maps_free
     procedure :: write => coop_healpix_maps_write
     procedure :: read => coop_healpix_maps_read
     procedure :: map2alm => coop_healpix_maps_map2alm
     procedure :: alm2map => coop_healpix_maps_alm2map
     procedure :: simulate => coop_healpix_maps_simulate
     procedure :: simulate_Tmaps => coop_healpix_maps_simulate_Tmaps
     procedure :: simulate_TQUmaps => coop_healpix_maps_simulate_TQUmaps
     procedure :: iqu2TEB => coop_healpix_maps_iqu2TEB
     procedure :: iqu2TQTUT => coop_healpix_maps_iqu2TQTUT
     procedure :: smooth => coop_healpix_smooth_map
     procedure :: smooth_mask => coop_healpix_smooth_mask
     procedure :: convert2nested => coop_healpix_convert_to_nested
     procedure :: convert2ring => coop_healpix_convert_to_ring
     procedure :: filter_alm =>  coop_healpix_filter_alm
     procedure :: stack =>     coop_healpix_stack
  end type coop_healpix_maps



#define COS2RADIUS(cosx) (sqrt(2.d0*(1.d0 - (cosx))))
#define RADIUS2COS(r)  (1.d0-(r)**2/2.d0)

contains

  subroutine coop_healpix_maps_simulate(this)
    class(coop_healpix_maps) this
    real(sp),dimension(:),allocatable::sqrtCls
    real(sp),dimension(:, :),allocatable::Cls_sqrteig
    real(sp),dimension(:,:,:),allocatable::Cls_rot
    integer l
    if(this%nmaps.eq.1 .and. this%spin(1).eq.0)then
       allocate(sqrtCls(0:this%lmax))
       !$omp parallel do
       do l = 0, this%lmax
          sqrtCls(l) = sqrt(this%Cl(l,1))
       enddo
       !$omp end parallel do
       call coop_healpix_maps_simulate_Tmaps(this, this%nside, this%lmax, sqrtCls)
       deallocate(sqrtCls)
    elseif(this%nmaps.eq.3 .and. this%iq .eq.2)then
       allocate(Cls_sqrteig(3, 0:this%lmax), Cls_rot(3,3,0:this%lmax))
       call coop_healpix_Cls2Rot(this%lmax, this%Cl, Cls_sqrteig, Cls_rot)
       call coop_healpix_maps_simulate_TQUmaps(this, this%nside, this%lmax, Cls_sqrteig, Cls_rot)
       deallocate(Cls_sqrteig, Cls_rot)
    else
       stop "unknown coop_healpix_maps_simulate mode"
    endif
  end subroutine coop_healpix_maps_simulate


  subroutine coop_healpix_maps_simulate_Tmaps(this, nside, lmax, sqrtCls)
    class(coop_healpix_maps) this
    integer nside
    integer lmax
    real(sp) sqrtCls(0:lmax)
    integer l,m
    call this%init( nside = nside, nmaps = 1, spin = (/ 0 /), lmax = lmax)
    !$omp parallel do private(l, m)
    do l=0, lmax
       this%alm(l, 0, 1) = coop_random_complex_Gaussian(.true.)*SqrtCls(l)     
       do m = 1, l
          this%alm(l, m, 1) = coop_random_complex_Gaussian()*SqrtCls(l)
       enddo
    enddo
    !$omp end parallel do
    call coop_healpix_maps_alm2map(this)
  end subroutine coop_healpix_maps_simulate_Tmaps


  subroutine coop_healpix_get_Cls(this) !!I assume you have already called    this_map2alm(this)
    type(coop_healpix_maps)this
    integer l, m, i, j, k
    if(.not.allocated(this%alm)) stop "coop_healpix_get_Cls: you have to call coop_healpix_maps_map2alm before calling this subroutine"
    !$omp parallel do private(i,j,k,l)
    do i=1, this%nmaps
       do j=1, i
          k = coop_matsym_index(this%nmaps, i, j)
          do l = 0, this%lmax
             this%Cl(l, k) = (sum(COOP_MULT_REAL(this%alm(l, 1:l, i), this%alm(l, 1:l, j))) + 0.5d0 * COOP_MULT_REAL(this%alm(l,0,i), this%alm(l,0,j)) )/(l+0.5d0)
          enddo
       enddo
    enddo
    !$omp end parallel do
  end subroutine coop_healpix_get_Cls

  subroutine coop_healpix_Cls2Rot(lmax, Cls, Cls_sqrteig, Cls_rot)
    integer lmax
    real(sp),dimension(0:lmax, 6),intent(IN)::Cls !!ordering is TT, EE, BB, TE, EB, TB
    real(sp), dimension(3, 0:lmax),intent(OUT)::Cls_sqrteig
    real(sp), dimension(3, 3, 0:lmax),intent(OUT)::Cls_rot
    integer l
    real(dl) a2(2,2), a3(3,3)
    real(dl) psi2(2,2), psi3(3,3)
    if(all(Cls(:,coop_healpix_index_EB).eq.0.d0) .and. all(Cls(:, coop_healpix_index_TB).eq.0.d0))then
       Cls_sqrteig(coop_healpix_index_BB,:) = sqrt(Cls(:, coop_healpix_index_BB))
       Cls_rot(coop_healpix_index_BB, coop_healpix_index_TT, :) = 0
       Cls_rot(coop_healpix_index_BB, coop_healpix_index_EE, :) = 0
       Cls_rot(coop_healpix_index_TT, coop_healpix_index_BB, :) = 0
       Cls_rot(coop_healpix_index_EE, coop_healpix_index_BB, :) = 0
       Cls_rot(coop_healpix_index_BB, coop_healpix_index_BB, :) = 1.
       do l=0, lmax
          a2(1,1) = Cls(l, coop_healpix_index_TT)
          a2(2,2) = Cls(l, coop_healpix_index_EE)
          a2(1,2) = Cls(l, coop_healpix_index_TE)
          a2(2,1) = a2(1,2)
          call coop_matsymdiag_small(2, a2, psi2)
          Cls_sqrteig(coop_healpix_index_TT, l) = sqrt(a2(1,1))
          Cls_sqrteig(coop_healpix_index_EE, l) = sqrt(a2(2,2))
          Cls_rot( coop_healpix_index_TT:coop_healpix_index_EE, coop_healpix_index_TT:coop_healpix_index_EE, l) = psi2
       end do
    else
       do l=0, lmax
          a3(1,1) = Cls(l,coop_healpix_index_TT)
          a3(2,2) = Cls(l,coop_healpix_index_EE)
          a3(3,3) = Cls(l,coop_healpix_index_BB)
          a3(1,2) = Cls(l,coop_healpix_index_TE)
          a3(2,3) = Cls(l,coop_healpix_index_EB)
          a3(3,1) = Cls(l,coop_healpix_index_TB)
          a3(2,1) = a3(1,2)
          a3(3,2) = a3(2,3)
          a3(1,3) = a3(3,1)
          call coop_matsymdiag_small(3, a3, psi3)
          Cls_sqrteig(coop_healpix_index_TT, l) = sqrt(a3(1,1))
          Cls_sqrteig(coop_healpix_index_EE, l) = sqrt(a3(2,2))
          Cls_sqrteig(coop_healpix_index_BB, l) = sqrt(a3(3,3))
          Cls_rot(:, :, l) = psi3
       end do
    endif
  end subroutine coop_healpix_Cls2Rot

  subroutine coop_healpix_maps_iqu2TQTUT(this)
    class(coop_healpix_maps) this
    call coop_healpix_maps_map2alm(this)
    this%alm(:,:,2) = this%alm(:,:,1)
    this%alm(:,:,3) = 0
    this%spin(2:3) = 2
    this%spin(1) = 0
    call coop_healpix_maps_alm2map(this)
  end subroutine coop_healpix_maps_iqu2TQTUT

  subroutine coop_healpix_maps_iqu2TEB(this)
    class(coop_healpix_maps) this
    call coop_healpix_maps_map2alm(this)
    this%spin = 0
    this%iq = 0
    this%iu = 0
    call coop_healpix_maps_alm2map(this)
  end subroutine coop_healpix_maps_iqu2TEB


  subroutine coop_healpix_maps_simulate_TQUmaps(this, nside, lmax, Cls_sqrteig, Cls_rot)
    class(coop_healpix_maps) this
    integer lmax, nside
    real(sp),dimension(3, 0:lmax)::Cls_sqrteig
    real(sp),dimension(3, 3, 0:lmax)::Cls_rot
    integer l, m
    call this%init(nside = nside, nmaps = 3, spin = (/ 0, 2, 2 /), lmax = lmax)    
    !$omp parallel do private(l, m)
    do l=0, lmax
       this%alm(l, 0, :) = matmul(Cls_rot(:, :, l), Cls_sqrteig(:,l) * (/ coop_random_complex_Gaussian(.true.), coop_random_complex_Gaussian(.true.), coop_random_complex_Gaussian(.true.) /) )
       do m = 1, l
          this%alm(l, m, :) = matmul(Cls_rot(:, :, l), Cls_sqrteig(:,l) * (/ coop_random_complex_Gaussian(), coop_random_complex_Gaussian(), coop_random_complex_Gaussian() /) )
       enddo
    enddo
    !$omp end parallel do
    call coop_healpix_maps_alm2map(this)
  end subroutine coop_healpix_maps_simulate_TQUmaps


  subroutine coop_healpix_maps_init(this, nside, nmaps, spin, lmax)
    class(coop_healpix_maps) this
    integer:: nside, nmaps
    integer:: spin(nmaps)
    integer, optional::lmax
    if(allocated(this%map))then
       if(this%nside .eq. nside .and. this%nmaps.eq.nmaps)then
          goto 100
       endif
       deallocate(this%map)
    endif
    if(allocated(this%spin))deallocate(this%spin)
    this%nside = nside
    this%nmaps = nmaps
    this%npix = nside2npix(nside)
    allocate(this%map(0:this%npix - 1, nmaps))
    allocate(this%spin(this%nmaps))
100 this%spin = spin
    if(all(this%spin(1:this%nmaps-1) .ne. 2))then
       this%iq = 0
       this%iu = 0
    else
       this%iq = 1
       do while(this%spin(this%iq) .ne. 2)
          this%iq = this%iq + 1
       enddo
       this%iu = this%iq + 1
       if(this%spin(this%iu).ne.2)then
          this%iq = 0
          this%iu = 0
       endif
    endif
    if(present(lmax))then
       if(allocated(this%alm))then
          if(this%lmax  .eq. lmax)then
             goto 200
          endif
          deallocate(this%alm)
       endif
       if(allocated(this%cl))deallocate(this%cl)
       this%lmax = lmax
       allocate(this%alm(0:this%lmax, 0:this%lmax, this%nmaps))
       allocate(this%cl(0:this%lmax, this%nmaps*(this%nmaps+1)/2))
    endif
200 this%ordering = COOP_RING !!default ordering
    call write_minimal_header(this%header,dtype = 'MAP', nside=this%nside, order = this%ordering, creator='Zhiqi Huang', version = 'CosmoLib', units='muK', polar=any(this%spin.eq.2) )
    this%maskpol_npix = 0
  end subroutine coop_healpix_maps_init

  subroutine coop_healpix_maps_free(this)
    class(coop_healpix_maps) this
    if(allocated(this%map))deallocate(this%map)
    if(allocated(this%alm))deallocate(this%alm)
    if(allocated(this%cl))deallocate(this%cl)
    if(allocated(this%spin))deallocate(this%spin)
    if(allocated(this%mask_listpix))deallocate(this%mask_listpix)
  end subroutine coop_healpix_maps_free

  subroutine coop_healpix_maps_read(this, filename, nmaps_wanted, spin)
    class(coop_healpix_maps) this
    COOP_UNKNOWN_STRING filename
    integer,optional::nmaps_wanted
    integer,dimension(:),optional::spin
    integer(8) npixtot
    integer nmaps_actual
    if(.not. coop_file_exists(filename))then
       write(*,*) trim(filename)
       stop "cannot find the file"
    endif
    npixtot = getsize_fits(trim(filename), nmaps = nmaps_actual, nside = this%nside, ordering = this%ordering)
    this%npix =nside2npix(this%nside)
    if(present(nmaps_wanted))then       
       this%nmaps = nmaps_wanted
       if(nmaps_wanted .lt. nmaps_actual)then
          nmaps_actual = nmaps_wanted
       endif
    else
       this%nmaps = nmaps_actual
    endif
    if(allocated(this%spin))then
       if(size(this%spin) .ne. this%nmaps)then
          deallocate(this%spin)
          allocate(this%spin(this%nmaps))
       endif
    else
       allocate(this%spin(this%nmaps))
    endif
    if(present(spin))then
       if(size(spin).ne. this%nmaps)then
          stop "coop_healpix_maps_read: the list of spins should have the same size as nmaps"
       else
          this%spin = spin
          this%iq = 1
          do while(this%spin(this%iq) .ne.2 .and. this%iq .lt. this%nmaps)
             this%iq = this%iq + 1
          enddo
          if(this%iq .ge. this%nmaps)then
             this%iq = 0
             this%iu = 0
          else
             this%iu = this%iq + 1
          endif
       endif
    else
       select case(this%nmaps)
       case(3)
          this%spin = 0
          this%spin(2:3) = 2
          this%iq = 2
          this%iu = 3
          write(*,*) this%nmaps, " for nmaps = 3 I assume it is an IQU map, specify spins otherwise"
       case(2)  
          this%spin(1:2) = 2
          this%iq = 1
          this%iu = 2
          write(*,*) this%nmaps, " for nmaps = 2 I assume it is an QU map, specify spins otherwise"
       case default
          this%iq = 0
          this%iu = 0
          this%spin = 0
          write(*,*) this%nmaps, " for nmaps !=2,3  I assume all maps are scalar, specify spins otherwise"
       end select
    endif
    if(allocated(this%map))then
       if(size(this%map, 1).ne. this%npix .or. size(this%map, 2).ne.this%nmaps)then
          deallocate(this%map)
          allocate(this%map(0:this%npix-1, this%nmaps))
       endif
    else
       allocate(this%map(0:this%npix-1, this%nmaps))
    endif

    call input_map(trim(filename), this%map, this%npix, nmaps_actual, fmissval = 0.)
    call this%convert2ring
    call write_minimal_header(this%header,dtype = 'MAP', nside=this%nside, order = this%ordering, creator='Zhiqi Huang', version = 'CosmoLib', units='muK', polar=any(this%spin.eq.2) )

  end subroutine coop_healpix_maps_read

  subroutine coop_healpix_maps_write(this, filename, index_list)
    class(coop_healpix_maps)this
    COOP_UNKNOWN_STRING filename
    integer,dimension(:),optional::index_list
    logical pol
    if(present(index_list))then
       if(any(index_list .lt. 1 .or. index_list .gt. this%nmaps)) stop "coop_healpix_write_map: index out of range"
       pol = any(this%spin(index_list).eq.2)
    else
       pol =any(this%spin.eq.2)
    endif
    call coop_delete_file(trim(filename))
    if(allocated(this%alm))then
       call write_minimal_header(this%header,dtype = 'MAP', nside=this%nside, order = this%ordering, creator='Zhiqi Huang', version = 'CosmoLib', units='muK', nlmax = this%lmax, nmmax = this%lmax, polar= pol)
    else
       call write_minimal_header(this%header,dtype = 'MAP', nside=this%nside, order = this%ordering, creator='Zhiqi Huang', version = 'CosmoLib', units='muK', polar= pol )
    endif
    if(present(index_list))then
       call output_map(this%map(:, index_list), this%header, trim(filename))
    else
       call output_map(this%map, this%header, trim(filename))
    endif
  end subroutine coop_healpix_maps_write

  subroutine coop_healpix_convert_to_nested(this)
    class(coop_healpix_maps) this
    if(.not. allocated(this%map)) stop "coop_healpix_convert_to_nested: map is not allocated yet"
    if(this%ordering .eq. COOP_RING) then
       call convert_ring2nest(this%nside, this%map)
       this%ordering = COOP_NESTED
    elseif(this%ordering .ne. COOP_NESTED)then
       write(*,*) "ordering = ", this%ordering
       stop "coop_healpix_convert_to_nested: unknown ordering"
    endif
  end subroutine coop_healpix_convert_to_nested

  subroutine coop_healpix_convert_to_ring(this)
    class(coop_healpix_maps) this
    if(.not. allocated(this%map)) stop "coop_healpix_convert_to_ring: map is not allocated yet"
    if(this%ordering .eq. COOP_NESTED)then
       call convert_nest2ring(this%nside, this%map)
       this%ordering = COOP_RING
    elseif(this%ordering .ne. COOP_RING)then
       write(*,*) "ordering = ", this%ordering
       stop "coop_healpix_convert_to_ring: UNKNOWN ordering"
    endif
  end subroutine coop_healpix_convert_to_ring

  subroutine coop_healpix_maps_map2alm(this, lmax)
    class(coop_healpix_maps) this
    integer,optional::lmax
    integer i, l
    complex, dimension(:,:,:),allocatable::alm
    call this%convert2ring()
    if(present(lmax))then
       if(lmax .gt. this%nside*3)then
          write(*,*) "lmax > nside x 3 is not recommended"
          stop
       else
          this%lmax = lmax          
       endif
    else
       this%lmax =  min(coop_healpix_default_lmax, this%nside*2)
    endif
    if(allocated(this%alm))then
       if(size(this%alm, 1) .ne. this%lmax+1 .or. size(this%alm, 2) .ne. this%lmax+1 .or. size(this%alm, 3) .ne. this%nmaps)then
          deallocate(this%alm)
          allocate(this%alm(0:this%lmax, 0:this%lmax, this%nmaps))
       endif
    else
       allocate(this%alm(0:this%lmax, 0:this%lmax, this%nmaps))
    endif
    this%alm = 0.
    if(allocated(this%cl))then
       if(size(this%cl, 1) .ne. this%lmax+1 .or. size(this%cl, 2) .ne. this%nmaps*(this%nmaps+1)/2)then
          deallocate(this%cl)
          allocate(this%cl(0:this%lmax, this%nmaps*(this%nmaps+1)/2))
       endif
    else
       allocate(this%cl(0:this%lmax, this%nmaps*(this%nmaps+1)/2))
    endif

    i = 1
    do while(i.le. this%nmaps)
       if(this%spin(i).eq.0)then
          call map2alm(this%nside, this%lmax, this%lmax, this%map(:,i), this%alm(:,:,i:i))
          i = i + 1
       else
          if(.not. allocated(alm))allocate(alm(2, 0:this%lmax, 0:this%lmax))
          if(i.lt. this%nmaps)then
             if(this%spin(i+1) .eq. this%spin(i))then
                call map2alm_spin(this%nside, this%lmax, this%lmax, this%spin(i), this%map(:,i:i+1), alm)
                this%alm(:,:,i) = alm(1, :, :)
                this%alm(:,:,i+1) = alm(2, :, :)
                i = i + 2
                cycle
             endif
          endif
          write(*,*) this%spin
          stop "coop_healpix_maps_map2alm: nonzero spin maps must appear in pairs"
       endif
    enddo
    if(allocated(alm))deallocate(alm)
    call coop_healpix_get_Cls(this)
  end subroutine coop_healpix_maps_map2alm


  subroutine coop_healpix_maps_alm2map(this)
    class(coop_healpix_maps) this
    integer i
    complex,dimension(:,:,:),allocatable::alm
    i = 1
    do while(i.le. this%nmaps)
       if(this%spin(i).eq.0)then
          call alm2map(this%nside, this%lmax, this%lmax, this%alm(:,:,i:i), this%map(:,i))
          i = i + 1
       else
          if(.not.allocated(alm))allocate(alm(2,0:this%lmax, 0:this%lmax))
          if(i.lt. this%nmaps)then
             alm(1,:,:) = this%alm(:,:,i)
             alm(2,:,:) = this%alm(:,:,i+1)
             if(this%spin(i+1) .eq. this%spin(i))then
                call alm2map_spin(this%nside, this%lmax, this%lmax, this%spin(i), alm, this%map(:,i:i+1))
                i = i + 2
                cycle
             endif
          endif
          stop "coop_healpix_maps_alm2map: nonzero spin maps must appear in pairs"
       endif
    enddo
    if(allocated(alm))deallocate(alm)
  end subroutine coop_healpix_maps_alm2map

  subroutine coop_healpix_filter_alm(this, fwhm, lpower, window)
    class(coop_healpix_maps) this
    real(sp),optional::window(0:this%lmax)
    real(sp),optional::fwhm
    real(sp),optional::lpower
    integer l
    real(sp) c, w(0:this%lmax)
    w = 1.
    if(present(fwhm))then
       c = sign((coop_sigma_by_fwhm * fwhm)**2/2., dble(fwhm))
       !$omp parallel do
       do l = 0,  this%lmax
          w(l) = w(l)*exp(-l*(l+1.)*c)
       enddo
       !$omp end parallel do
    endif
    if(present(lpower))then
       !$omp parallel do
       do l = 0,  this%lmax
          w(l) = w(l)*(l*(l+1.))**(lpower/2.)
       enddo
       !$omp end parallel do
    endif
    if(present(window))then
       !$omp parallel do
       do l = 0,  this%lmax
          w(l) = w(l)*window(l)
       enddo
       !$omp end parallel do       
    endif
    !$omp parallel do
    do l = 0, this%lmax
       this%alm(l,:,:) = this%alm(l,:,:)*w(l)
       this%Cl(l,:) = this%Cl(l,:)*w(l)**2
    enddo
    !$omp end parallel do
  end subroutine coop_healpix_filter_alm


  subroutine split_angular_mode(n, qmap, umap, m, nr, fr)
    integer n, m, nr
    real(sp) qmap(-n:n,-n:n), umap(-n:n,-n:n)
    real(sp) fr(0:nr), w(0:nr), q, u, r, phi, fpoint
    integer i, j, ir
    fr = 0
    w = 0
    do i = -n, n
       do j = -n, n
          r = sqrt(real(i)**2 + real(j)**2)
          ir = floor(r)          
          if(ir .le. nr)then
             phi = m*COOP_POLAR_ANGLE(real(i), real(j))
             r = r - ir
             fpoint = qmap(i,j)*cos(phi) + umap(i,j)*sin(phi)
             fr(ir) = fr(ir) + fpoint*(1.d0-r)
             w(ir) = w(ir) + 1.d0-r
             if(ir.ne.nr)then
                fr(ir+1) = fr(ir+1)+fpoint*r
                w(ir+1) = w(ir+1)+r
             endif
          endif
       enddo
    enddo
    do ir = 0, nr
       if(w(ir).gt.0.)then
          fr(ir) = fr(ir)/w(ir)
       endif
    enddo
    do ir = n, nr !!damp the amplitude in the corners
       fr(ir) = fr(ir)*exp(-((ir-n+1.)/n*(1.414/0.414))**2)
    enddo
    if(m.ne.0) fr(0) = 0
  end subroutine split_angular_mode


  subroutine map_filter_modes(n, qmap, umap, ms)
    integer n, nm
    integer ms(:)
    real(sp) qmap(-n:n, -n:n), umap(-n:n, -n:n)
    real(sp),dimension(:,:),allocatable::fr
    real(sp) r, phi, s1, s2
    integer i, j, ir, nr, im
    nm = size(ms)
    nr = ceiling(coop_sqrt2*n)+1
    allocate(fr(0:nr, nm))
    do im = 1, nm
       call split_angular_mode(n, qmap, umap, ms(im), nr, fr(0:nr, im))
    enddo
    qmap = 0
    umap = 0
    do i=-n, n
       do j=-n,n
          r = sqrt(real(i)**2 + real(j)**2)
          ir = floor(r)
          r = r - ir
          phi = COOP_POLAR_ANGLE(real(i), real(j))
          do  im =1, nm
             qmap(i,j) = qmap(i,j) + (fr(ir,im)*(1.-r)+fr(ir+1,im)*r)*cos(ms(im)*phi)
             umap(i,j) = umap(i,j) + (fr(ir,im)*(1.-r)+fr(ir+1,im)*r)*sin(ms(im)*phi)
             
          enddo
       enddo
    enddo
    deallocate(fr)
  end subroutine map_filter_modes


  subroutine coop_healpix_get_disc(nside, pix, disc)
    integer pix, nside
    type(coop_healpix_disc) disc
    real(dl) r
    disc%nside  = nside
    disc%center = pix
    call pix2ang_ring(nside, pix, disc%theta, disc%phi)
    call ang2vec(disc%theta, disc%phi, disc%nz)
    disc%nx = (/  sin(disc%phi) , - cos(disc%phi) , 0.d0 /)
    call coop_vector_cross_product(disc%nz, disc%nx, disc%ny)
  end subroutine coop_healpix_get_disc

  subroutine coop_healpix_disc_pix2ang(disc, pix, r, phi)
    class(coop_healpix_disc) disc
    integer pix
    real(dl) r, phi, vec(3), x, y
    if(pix .eq. disc%center)then
       r = 0
       phi = 0
       return
    endif
    call pix2vec_ring(disc%nside, pix, vec)
    r = COS2RADIUS( dot_product(vec, disc%nz) )
    x = dot_product(vec, disc%nx)
    y = dot_product(vec, disc%ny)
    phi = COOP_POLAR_ANGLE(x, y)
  end subroutine coop_healpix_disc_pix2ang

  subroutine coop_healpix_disc_ang2pix(disc, r, phi, pix)
    class(coop_healpix_disc) disc
    real(dl) r !!in unit of radian
    real(dl) phi, vec(3), cost, sint
    integer pix
    cost = RADIUS2COS(r)
    sint = sqrt(1.d0 - cost**2)
    vec = sint*cos(phi)* disc%nx + sint*sin(phi)*disc%ny + cost*disc%nz
    call vec2pix_ring(disc%nside, vec, pix)
  end subroutine coop_healpix_disc_ang2pix


  subroutine coop_healpix_disc_pix2xy(disc, pix, x, y)
    class(coop_healpix_disc) disc
    integer pix
    real(dl) r, phi, vec(3), x, y
    if(pix .eq. disc%center)then
       x = 0
       y = 0
       return
    endif
    call pix2vec_ring(disc%nside, pix, vec)
    r = COS2RADIUS( dot_product(vec, disc%nz) )
    x = dot_product(vec, disc%nx)
    y = dot_product(vec, disc%ny)
    r = r/sqrt(x**2+y**2)
    x = r * x
    y = r * y
  end subroutine coop_healpix_disc_pix2xy


  subroutine coop_healpix_disc_xy2pix(disc, x, y, pix)
    class(coop_healpix_disc) disc
    real(dl) x, y !!in unit of radian
    real(dl) vec(3), cost, sint, r
    integer pix
    r = sqrt(x**2+y**2)
    if(r.lt.1.d-8)then
       pix = disc%center
       return
    endif
    cost = RADIUS2COS(r)
    sint = sqrt(1.d0 - cost**2)
    vec = sint*(x/r)* disc%nx + sint*(y/r)*disc%ny + cost*disc%nz
    call vec2pix_ring(disc%nside, vec, pix)
  end subroutine coop_healpix_disc_xy2pix

  subroutine coop_healpix_rotate_qu(qu, phi)
    real(sp) qu(2)
    real(dl) phi, cosp, sinp
    cosp = cos(2.d0*phi)
    sinp = sin(2.d0*phi)
    qu = (/ qu(1)*cosp + qu(2)*sinp,  -qu(1)*sinp + qu(2)*cosp /)
  end subroutine coop_healpix_rotate_qu

  subroutine coop_healpix_stack(this, disc, n, rpix, angle, stack_option, image, uimage, mask, counter)
    class(coop_healpix_maps) this
    character(LEN=*) stack_option
    type(coop_healpix_disc) disc
    real(sp) qu(2)
    integer n
    real(sp) image(-n:n, -n:n), tmpq(-n:n, -n:n), tmpu(-n:n, -n:n)
    real(sp),optional::uimage(-n:n, -n:n)
    real(dl) rpix, angle
    integer i, j, pix
    real(dl) r, phi,  x, y
    type(coop_healpix_maps),optional::mask
    real(sp) mask_count
    real(sp) counter
    tmpq = 0
    tmpu = 0
    mask_count = 0
    select case(trim(stack_option))
    case("T", "E", "B")
       do i = -n, n
          do j = -n, n
             x = rpix*i
             y = rpix*j
             r = sqrt(x**2+y**2)
             phi = COOP_POLAR_ANGLE(x, y) + angle
             call coop_healpix_disc_ang2pix(disc, r, phi, pix)
             if(present(mask))then
                if(mask%map(pix,1) .gt. 0.5)then
                   mask_count = mask_count + mask%map(pix, 1)
                   tmpq(i, j) = tmpq(i, j) + this%map(pix,1)*mask%map(pix,1)
                endif
             else 
                tmpq(i, j) = tmpq(i, j) + this%map(pix,1)
             endif
          enddo
       enddo
    case("Q", "U")
       do i = -n, n
          do j = -n, n
             x = rpix*i
             y = rpix*j
             r = sqrt(x**2+y**2)
             phi = COOP_POLAR_ANGLE(x, y) + angle
             call coop_healpix_disc_ang2pix(disc, r, phi, pix)
             if(present(mask)) then
                if(mask%map(pix, 1) .gt. 0.5)then
                   qu = this%map(pix, this%iq:this%iu)
                   call coop_healpix_rotate_qu(qu, angle)
                   mask_count = mask_count + mask%map(pix, 1) 
                   tmpq(i, j) = tmpq(i, j) + qu(1)*mask%map(pix, 1)
                   tmpu(i, j) = tmpu(i, j) + qu(2)*mask%map(pix, 1)
                endif
             else
                qu = this%map(pix, this%iq:this%iu)
                call coop_healpix_rotate_qu(qu, angle)
                tmpq(i, j) = tmpq(i, j) + qu(1)
                tmpu(i, j) = tmpu(i, j) + qu(2)
             endif
          enddo
       enddo
    case("Qr", "QR", "Ur", "UR")
       do i = -n, n
          do j = -n, n
             x = rpix*i
             y = rpix*j
             r = sqrt(x**2+y**2)
             phi = COOP_POLAR_ANGLE(x, y) + angle
             call coop_healpix_disc_ang2pix(disc, r, phi, pix)
             if(present(mask))then
                if(mask%map(pix, 1) .gt. 0.5)then
                   qu = this%map(pix, this%iq:this%iu)
                   call coop_healpix_rotate_qu(qu, phi)
                   tmpq(i, j) = tmpq(i, j) + qu(1)*mask%map(pix, 1)
                   tmpu(i, j) = tmpu(i, j) + qu(2)*mask%map(pix, 1)
                   mask_count = mask_count + mask%map(pix, 1) 
                endif
             else
                qu = this%map(pix, this%iq:this%iu)
                call coop_healpix_rotate_qu(qu, phi)
                tmpq(i, j) = tmpq(i, j) + qu(1)
                tmpu(i, j) = tmpu(i, j) + qu(2)
                
             endif
          enddo
       enddo
    case default
       write(*,*) "coop_healpix_stack: Unknown stack_option"//trim(stack_option)
       stop
    end select
    if(present(mask) .and. mask_count .lt. (2*n+1.)**2*coop_healpix_mask_tol)then
       return
    endif
    if(present(mask))then
       counter = counter + mask_count/(2*n+1.)**2
    else
       counter = counter + 1
    endif
    select case(trim(stack_option))
    case("T", "E", "B")
       image = image + tmpq
    case("Q", "Qr", "QR")
       image = image +  tmpq
       if(present(uimage)) uimage = uimage + tmpu
    case("U", "Ur", "UR")
       image = image + tmpu
       if(present(uimage)) stop "coop_healpix_stack: for U stacking this should not happen"
    end select
    
  end subroutine coop_healpix_stack


  subroutine coop_healpix_stack_image(map_file, mask_file, spots_file, smooth_fwhm, stack_option, stm)
    COOP_UNKNOWN_STRING::map_file, mask_file, spots_file, stack_option
    real(dl) smooth_fwhm
    type(coop_healpix_maps) map, mask
    type(coop_healpix_stacked_map):: stm
    logical::do_mask
    integer nspots
    type(coop_file) sfp
    integer i, ithread, pix
    real(dl),dimension(:),allocatable::theta, phi, angle_rotate
    type(coop_healpix_disc),dimension(:),allocatable::disc
    if(.not. coop_file_exists(spots_file))then
       write(*,*) trim(spots_file)//" does not exist"
       stop
    endif
    if(.not. coop_file_exists(map_file))then
       write(*,*) trim(map_file)//" does not exist"
       stop
    endif
    if(.not. coop_file_exists(mask_file))then
       write(*,*) trim(mask_file)//" does not exist"
       stop
    endif 
    if(trim(stack_option).eq. "T" .or. trim(stack_option).eq. "E" .or. trim(stack_option).eq. "B")then
       call map%read(map_file, nmaps_wanted = 1)
       stm%want_qu  = .false.
    else
       call map%read(map_file)
       stm%want_qu = .true.
       if(map%nmaps .lt. 2) stop "For Q, U stacking you need at least two maps"
    endif
    call map%smooth(smooth_fwhm)
    if(trim(mask_file).eq."")then
       do_mask = .false.
    else
       call mask%read(mask_file, nmaps_wanted = 1)
       do_mask = .true.
    endif
    nspots = coop_file_numlines(spots_file)
    allocate(theta(nspots), phi(nspots), angle_rotate(nspots))
    call sfp%open(trim(spots_file), "r")
    do i=1, nspots
       read(sfp%unit, *) theta(i), phi(i), angle_rotate(i)       
    enddo
    call sfp%close()
    allocate(disc(stm%n_threads))
    if(allocated(stm%image))deallocate(stm%image)
    allocate(stm%image(-stm%n:stm%n, -stm%n:stm%n, stm%n_threads)
    if(stm%want_qu)then
       if(allocated(stm%uimage))deallocate(stm%uimage)
       allocate(stm%uimage(-stm%n:stm%n, -stm%n:stm%n, stm%n_threads)
    endif
    if(stm%want_sq)then
       if(allocated(stm%sq))deallocate(stm%sq)
       allocate(stm%image(-stm%n:stm%n, -stm%n:stm%n, stm%n_threads)
       if(stm%want_qu)then
          if(allocated(stm%uimage))deallocate(stm%uimage)
          allocate(stm%uimage(-stm%n:stm%n, -stm%n:stm%n, stm%n_threads)
       endif

    endif
    if(stm%want_qu)then
       !$omp parallel do private(i, ithread, pix)
       do ithread = 1, n_threads
          do i = ithread, nspots, n_threads
             call ang2pix_ring(map%nside, theta(i), phi(i), pix)
             call coop_healpix_get_disc(map%nside, pix, disc(ithread))
             if(do_mask)then
                call coop_healpix_stack( map, disc(ithread), n, r_resolution, angle_rotate(i), stack_option, image(:,:,ithread), uimage(:,:, ithread), mask = mask, counter =  nstack(ithread))
             else
                call coop_healpix_stack( map, disc(ithread), n, r_resolution, angle_rotate(i), stack_option, stm%image(:,:,ithread), stm%uimage(:,:, ithread), counter = stm%nstack(ithread))
             endif
          enddo
       enddo
       !$omp end parallel do
    else
       !$omp parallel do private(i, ithread, pix) 
       do ithread = 1, stm%n_threads
          do i = ithread, nspots, stm%n_threads
             call ang2pix_ring(map%nside, theta(i), phi(i), pix)
             call coop_healpix_get_disc(map%nside, pix, disc(ithread))
             if(do_mask)then
                call coop_healpix_stack(map, disc(ithread), stm%n, stm%dr, angle_rotate(i), stack_option, stm%image(:,:,ithread), mask = mask, counter =  nstack(ithread))
             else
                call coop_healpix_stack(map, disc(ithread), n, r_resolution, angle_rotate(i), stack_option, image(:,:,ithread), counter = nstack(ithread))
             endif
          enddo
       enddo
       !$omp end parallel do
    endif

    deallocate(theta, phi, angle_rotate)
    deallocate(disc)
  end subroutine coop_healpix_stack_image


  subroutine coop_healpix_stack_io(map_file, mean_image_file, spots_file, rmax, r_resolution, stack_option, title, headless_vector, m_filter, caption, mask_file, pre_smooth_fwhm, post_smooth_fwhm, color_table, symmetric, min_val, max_val, output)
    type(coop_healpix_stacked_map):: stm
    type(coop_healpix_stacked_map),optional:: output
    COOP_UNKNOWN_STRING, optional::mask_file, color_table
    COOP_UNKNOWN_STRING::stack_option, title, map_file, mean_image_file, spots_file
    real(sp),optional::min_val, max_val
    COOP_SHORT_STRING:: ctbl
    type(coop_file)::fdata
    logical,optional::symmetric
    logical,optional::headless_vector
    COOP_UNKNOWN_STRING, optional::caption
    COOP_STRING the_caption, the_title
    integer,optional::m_filter(:)
    integer,parameter::n_threads = 4  !!must be >=2
    integer::mhs 
    real(dl),dimension(:),allocatable::theta, phi, angle_rotate
    real(dl) norm, thislen, x, y, xshift, yshift
    real(sp)  rot
    integer n, nblocks, pix, i,   j, k, space, ithread,  nspots, imf
    real(dl) rmax, r_resolution
    type(coop_healpix_disc) disc(n_threads)
    type(coop_asy) fp
    type(coop_file) sfp
    real(sp),dimension(:),allocatable::xstart, ystart, xend, yend
    type(coop_healpix_maps) mask, map
    logical do_mask
    real(dl),optional::pre_smooth_fwhm
    real(dl),optional::post_smooth_fwhm
    real(sp) sigma
    integer nw
    real(sp),dimension(:,:),allocatable::wrap_image, window
    logical sym
    COOP_STRING mpost
    real(sp) zmin, zmax

    if(present(symmetric))then
       sym = symmetric
    else
       sym = .true.
    endif

    if(present(color_table))then
       ctbl = color_table
    else
       ctbl = "Rainbow"
    endif
    do_mask = .false.
    if(present(mask_file))then
       if(trim(mask_file).ne."")then
          call mask%read(mask_file, nmaps_wanted = 1)
          if(map%nside .ne. mask%nside) stop "coop_healpix_stack_io: mask must have the same resolution"
          do_mask = .true.
       endif
    endif
    disc%nside = map%nside
    
    if((trim(stack_option).eq."Qr" .or. trim(stack_option).eq."QR" .or. trim(stack_option).eq."Q").and. present(headless_vector))then
       if(headless_vector)then
          nblocks = 2  !!want headless vectors, too
       else
          nblocks = 1
       endif
    else
       nblocks = 1
    endif
    n = max(nint(rmax/r_resolution), 5)
    allocate(stm%image(-n:n, -n:n, n_threads))
    allocate(stm%sq(-n:n, -n:n, n_threads))
    allocate(stm%nstack(n_threads))
    stm%nstack = 0
    stm%image = 0.
    stm%sq = 0.
    if(nblocks.ne.1)then
       allocate(stm%uimage(-n:n, -n:n, n_threads))
       allocate(stm%usq(-n:n, -n:n, n_threads))
       stm%uimage = 0.
    endif
    deallocate(theta, phi, angle_rotate)    

    if(sum(nstack) .gt.0)then
       do i=-n, n
          do j=-n, n
             image(i, j, 1) = sum(image(i,j,:))/real(sum(nstack))
          enddo
       enddo
       if(nblocks.ne.1)then
          do i=-n, n
             do j=-n, n
                uimage(i, j, 1) = sum(uimage(i,j,:))/real(sum(nstack))
             enddo
          enddo
       endif
    else
       write(*,*) "no spots are listed in file "//trim(spots_file)
       stop
    endif

    if(present(post_smooth_fwhm))then
       sigma = post_smooth_fwhm * coop_sigma_by_fwhm
       nw = ceiling((sigma*3.)/r_resolution)
       if(nw.gt.1)then
          allocate(window(-nw:nw, -nw:nw), wrap_image(-n-nw:n+nw, -n-nw:n+nw))
          wrap_image = 0
          sigma = (r_resolution/sigma)**2/2.
          do i=-nw, nw
             do j=-nw, nw
                window(i,j) = exp(-(i**2+j**2)*sigma)
             enddo
          enddo
          window = window/sum(window)
          wrap_image(-n:n, -n:n) = image(-n:n, -n:n, 1)
          !$omp parallel do private(i,j)
          do i=-n, n
             do j=-n, n
                image(i, j, 1) = sum(window*wrap_image(i-nw:i+nw, j-nw:j+nw))
             enddo
          enddo
          !$omp end parallel do
          if(nblocks.ne.1)then
             wrap_image(-n:n, -n:n) = uimage(-n:n, -n:n, 1)
             !$omp parallel do private(i,j)
             do i=-n, n
                do j=-n, n
                   uimage(i, j, 1) = sum(window*wrap_image(i-nw:i+nw, j-nw:j+nw))
                enddo
             enddo
             !$omp end parallel do
          endif
          deallocate(window, wrap_image)
       endif
    endif
    
    write(*,*) "Stacked on "//trim(coop_num2str(nint(sum(nstack))))//" spots"

    if(present(caption))then
       if(caption(1:1).eq."#")then
          the_caption = trim(coop_num2str(nint(sum(nstack))))//" patches on "//trim(caption(2:))
       else
          the_caption = trim(caption)
       endif
    else
       the_caption =  trim(coop_num2str(nint(sum(nstack))))//" patches stacked"
    endif

    if(nblocks .ne. 1)then
       space = nint((n - 1)/7.)
       mhs = floor(real(n)/space - 0.5)
       allocate(xstart((2*mhs+1)**2), ystart((2*mhs+1)**2), xend((2*mhs+1)**2), yend((2*mhs+1)**2))
    endif
    if(.not. present(min_val) .or. .not. present(max_val))then
       call coop_array_get_threshold(image(-n:n,-n:n,1), 0.99_sp, zmin)
       call coop_array_get_threshold(image(-n:n,-n:n,1), 0.01_sp, zmax)
       if(sym)then
          zmax = max(abs(zmax), abs(zmin))
          zmin = -zmax
       endif
    endif
    if(present(min_val))zmin = min_val
    if(present(max_val))zmax = max_val
    call do_write_file(trim(mean_image_file))
    if(present(output))then
       output%n = n
       output%dr = r_resolution
    endif

    if(stack_option.eq."Q" .and. present(m_filter) .and. nblocks.ne.1)then
       image(:,:,2) = image(:,:,1)
       uimage(:,:,2) = uimage(:,:,1)
       do imf = 1, size(m_filter)
          call map_filter_modes(n, image(:,:,1), uimage(:,:,1), m_filter(imf:imf))
          call do_write_file(trim(coop_file_add_postfix(mean_image_file, "_m="//trim(coop_num2str(m_filter(imf))))))
          image(:,:,1) = image(:,:,2)
          uimage(:,:,1) = uimage(:,:,2)

          if(imf .eq. 1)then
             mpost = "_m="//trim(coop_num2str(m_filter(imf)))
          else
             mpost=trim(mpost)//"-"//trim(coop_num2str(m_filter(imf)))
          endif
       enddo
       if(size(m_filter).gt.1)then
          call map_filter_modes(n, image(:,:,1), uimage(:,:,1), m_filter)
          call do_write_file(trim(coop_file_add_postfix(mean_image_file, trim(mpost))))
       endif
    endif
    if(nblocks.ne.1) deallocate(uimage, xstart, ystart, xend, yend)    
    deallocate(image) 
    call map%free()
    call mask%free()
    if(present(output))output = stm
    if(allocated(stm%image))deallocate(stm%image)
    if(allocated(stm%uimage))deallocate(stm%uimage)
    if(allocated(stm%usq))deallocate(stm%usq)
    if(allocated(stm%sq))deallocate(stm%sq)
  contains 

    subroutine do_write_file(fname)
      COOP_UNKNOWN_STRING fname
      call fp%open(trim(fname),"w")
      call fp%init( caption = trim(the_caption),  xlabel = "$2\sin(\theta/2)\cos\phi$", ylabel = "$2\sin(\theta/2)\sin\phi$", nblocks = nblocks) 
      call coop_asy_density(fp, image(-n:n,-n:n,1), real(-r_resolution*n), real(r_resolution*n), real(-r_resolution*n), real(r_resolution*n), trim(title), zmax = zmax, zmin = zmin, color_table = ctbl)
      if(nblocks .ne. 1)then !!headless vectors
         norm = r_resolution*space/sqrt(maxval(image(:,:,1)**2+uimage(:,:,1)**2))/2. * 0.975  !!*0.95 to avoid overlap
         k = 1
         do i = -mhs*space, mhs*space, space
            do j = -mhs*space, mhs*space, space
               x = i*r_resolution
               y = j*r_resolution
               rot = 0.5*COOP_POLAR_ANGLE(image(i, j,1), uimage(i, j,1)) 
               if(stack_option .eq. "Qr" .or. stack_option .eq. "QR") rot = rot + COOP_POLAR_ANGLE(x, y)
               thislen = norm*sqrt(uimage(i,j,1)**2 + image(i,j,1)**2)
               xshift = thislen*cos(rot)
               yshift = thislen*sin(rot)
               xstart(k) =  x - xshift
               ystart(k) = y - yshift
               xend(k) = x + xshift
               yend(K) = y + yshift
               k = k + 1
            enddo
         enddo
         call coop_asy_lines(fp, xstart, ystart, xend, yend, "black", "solid", 2.)
      endif
      call fp%close()
    end subroutine do_write_file

  end subroutine coop_healpix_stack_io

  subroutine coop_healpix_smooth_mapfile(mapfile, filter_fwhm)
    COOP_UNKNOWN_STRING mapfile
    type(coop_healpix_maps) map
    real(dl) filter_fwhm
    call map%read(mapfile)
    call coop_healpix_smooth_map(map, filter_fwhm)
    call map%write(trim(coop_file_add_postfix(trim(mapfile),"_smoothed_fwhm"//trim(coop_num2str(nint(filter_fwhm/coop_SI_arcmin)))//"arcmin")))
    call map%free()
  end subroutine coop_healpix_smooth_mapfile

  subroutine coop_healpix_smooth_map(map, filter_fwhm)
    class(coop_healpix_maps) map
    real(dl) filter_fwhm
    integer lmax
    lmax = min(ceiling(3./max(abs(filter_fwhm)*coop_sigma_by_fwhm, 1.d-6)), map%nside*3)
    if((lmax*filter_fwhm*coop_sigma_by_fwhm).lt. 0.02) return
    write(*,*) "Smoothing with lmax = ", lmax
    call coop_healpix_maps_map2alm(map, lmax)
    call coop_healpix_filter_alm(map, fwhm = real(filter_fwhm))
    call coop_healpix_maps_alm2map(map)
  end subroutine coop_healpix_smooth_map


  


  subroutine coop_healpix_getQU(Emap_file, QUmap_file)
    COOP_UNKNOWN_STRING Emap_file, QUmap_file
    type(coop_healpix_maps) hge, hgqu
    call hge%read(Emap_file,  nmaps_wanted = 1)
    call coop_healpix_maps_map2alm(hge)
    call hgqu%init(nside = hge%nside, nmaps = 2, spin =  (/ 2, 2 /), lmax=hge%lmax)
    hgqu%alm(:, :, 1) = hge%alm(:, :, 1)
    hgqu%alm(:, :, 2) = 0
    call coop_healpix_maps_alm2map(hgqu)
    call hgqu%write(QUmap_file)
    call hgqu%free()
    call hge%free()
  end subroutine coop_healpix_getQU

  subroutine coop_healpix_export_spots(map_file, spots_file, spot_type, threshold, mask_file, filter_fwhm)
    COOP_UNKNOWN_STRING map_file, spots_file, spot_type
    COOP_UNKNOWN_STRING, optional::mask_file
    real(dl),optional::threshold
    type(coop_file) fp
    real(dl) theta, phi, rotate_angle, fcut
    type(coop_healpix_maps) mask, map
    real(dl),optional::filter_fwhm
    real(dl) total_weight
    integer i, iq, iu, j
    integer nneigh, list(8)
    logical do_mask
    select case(trim(spot_type))
    case("Tmax_QTUTOrient", "PTmax", "PTmin")
       call map%read(trim(map_file), nmaps_wanted = 3)
       call map%iqu2TQTUT()
    case default
       call map%read(trim(map_file))
    end select
    if(present(filter_fwhm)) call map%smooth(filter_fwhm)
    do_mask = .false.
    if(present(mask_file))then
       if(trim(mask_file).ne."")then
          call mask%read(mask_file, nmaps_wanted = 1)
          do i=1, map%nmaps
             map%map(:,i) = map%map(:,i)*mask%map(:,1)
          enddo
          if(mask%nside .ne. map%nside) stop "coop_healpix_export_spots: mask and map must have the same nside"
          total_weight = sum(mask%map(:,1))
          do_mask = .true.
       else
          total_weight = map%npix
       endif
    else
       total_weight = map%npix
    endif
    call map%convert2nested
    if(do_mask)call mask%convert2nested

    call fp%open(trim(spots_file),"w")
    select case(trim(spot_type))
    case("Tmax", "Emax", "Bmax")  !!random orientation
       if(present(threshold))then
          fcut = threshold*sqrt(sum(map%map(:,1)**2)/total_weight)
       else
          fcut = -1.e30
       endif
       do i=0, map%npix-1
          if(do_mask)then
             if( map%map(i,1) .lt. fcut .or. mask%map(i, 1) .le. 0.5 ) cycle
             call neighbours_nest(map%nside, i, list, nneigh)  
             if ( all(map%map(list(1:nneigh),1).lt.map%map(i,1)) .and. all(mask%map(list(1:nneigh),1) .gt. 0.5 ) )then
                call random_number(rotate_angle)
                rotate_angle = rotate_angle*coop_2pi
                call pix2ang_nest(map%nside, i, theta, phi)
                write(fp%unit, "(3E16.7)") theta, phi, rotate_angle
             endif
          else
             if(map%map(i,1).lt.fcut )cycle
             call neighbours_nest(map%nside, i, list, nneigh)  
             if(all(map%map(list(1:nneigh),1).lt. map%map(i,1)))then
                call random_number(rotate_angle)
                rotate_angle = rotate_angle*coop_2pi
                call pix2ang_nest(map%nside, i, theta, phi)
                write(fp%unit, "(3E16.7)") theta, phi, rotate_angle
             endif
          endif
       enddo
    case("Tmin", "Emin", "Bmin")  !!random orientation
       if(present(threshold))then
          fcut = - threshold*sqrt(sum(map%map(:,1)**2)/total_weight)
       else
          fcut = 1.e30
       endif
       do i=0, map%npix-1
          if(do_mask)then
             if(map%map(i,1).gt.fcut .or. mask%map(i, 1) .le. 0.5)cycle
             call neighbours_nest(map%nside, i, list, nneigh)  
             if( all(map%map(list(1:nneigh),1) .gt. map%map(i,1)) .and. all(mask%map(list(1:nneigh), 1) .gt. 0.5 ) ) then
                call random_number(rotate_angle)
                rotate_angle = rotate_angle*coop_2pi
                call pix2ang_nest(map%nside, i, theta, phi)
                write(fp%unit, "(3E16.7)") theta, phi, rotate_angle
             endif
          else
             if(map%map(i,1).gt.fcut )cycle
             call neighbours_nest(map%nside, i, list, nneigh)  
             if(all(map%map(list(1:nneigh),1).gt.map%map(i,1)))then
                call random_number(rotate_angle)
                rotate_angle = rotate_angle*coop_2pi
                call pix2ang_nest(map%nside, i, theta, phi)
                write(fp%unit, "(3E16.7)") theta, phi, rotate_angle
             endif
          endif
       enddo
    case("Tmax_QTUTOrient") !!oriented with QU, maxima of T
       if(map%nmaps .lt. 3) stop "For Tmax_QTUTOrient mode you need 3 maps"
       if(present(threshold))then
          fcut = threshold*sqrt(sum(map%map(:,1)**2)/total_weight)
       else
          fcut = -1.e30
       endif
       do i=0, map%npix-1
          if(do_mask)then
             if( map%map(i,1) .lt. fcut .or. mask%map(i,1) .le. 0.5)cycle
             call neighbours_nest(map%nside, i, list, nneigh)  
             if(all(map%map(list(1:nneigh),1) .lt. map%map(i,1)) .and. all(mask%map(list(1:nneigh),1) .gt. 0.5)) then
                call pix2ang_nest(map%nside, i, theta, phi)
                rotate_angle = COOP_POLAR_ANGLE(map%map(i, 2), map%map(i, 3))/2.
                write(fp%unit, "(3E16.7)") theta, phi, rotate_angle
             endif
          else
             if(map%map(i,1) .lt. fcut)cycle
             call neighbours_nest(map%nside, i, list, nneigh)  
             if(all(map%map(list(1:nneigh),1) .lt. map%map(i,1)))then
                call pix2ang_nest(map%nside, i, theta, phi)
                rotate_angle = COOP_POLAR_ANGLE(map%map(i, 2), map%map(i, 3))/2.
                write(fp%unit, "(3E16.7)") theta, phi, rotate_angle
             endif
          endif
       enddo
    case("Tmin_QTUTOrient") !!oriented with QU, minima of T
       if(map%nmaps .lt. 3) stop "For Tmin_QTUTOrient mode you need 3 maps"
       if(present(threshold))then
          fcut = -threshold*sqrt(sum(map%map(:,1)**2)/total_weight)
       else
          fcut = 1.e30
       endif
       do i=0, map%npix-1
          if(do_mask)then
             if( map%map(i,1) .gt. fcut .or. mask%map(i,1) .le. 0.5) cycle
             call neighbours_nest(map%nside, i, list, nneigh)  
             if( all( map%map(list(1:nneigh), 1) .gt. map%map(i,1) ) .and. all(mask%map(list(1:nneigh),1) .gt. 0.5) ) then
                call pix2ang_nest( map%nside, i, theta, phi )
                rotate_angle = COOP_POLAR_ANGLE(map%map(i, 2), map%map(i, 3))/2.
                write(fp%unit, "(3E16.7)") theta, phi, rotate_angle
             endif
          else
             if(map%map(i,1) .gt. fcut)cycle
             call neighbours_nest(map%nside, i, list, nneigh)  
             if(all(map%map(list(1:nneigh),1).gt. map%map(i,1)))then
                call pix2ang_nest(map%nside, i, theta, phi)
                rotate_angle = COOP_POLAR_ANGLE(map%map(i, 2), map%map(i, 3))/2.
                write(fp%unit, "(3E16.7)") theta, phi, rotate_angle
             endif
          endif
       enddo
    case("Pmax", "PTmax")
       select case(map%nmaps)
       case(2:3)
          iq = map%nmaps - 1
          iu = iq + 1
       case default
          stop "For polarization you need to specify Q, U maps in the input file."
       end select
       if(present(threshold))then
          fcut = threshold**2*(sum(map%map(:,iq)**2 + map%map(:,iu)**2)/total_weight)
       else
          fcut = -1.e30
       endif
       do i=0, map%npix-1
          if(do_mask)then
             if( map%map(i,iq)**2 + map%map(i,iu)**2 .lt. fcut  .or.  mask%map(i, 1) .le. 0.5 ) cycle
             call neighbours_nest(map%nside, i, list, nneigh)  
             if( all( map%map(list(1:nneigh),iq)**2 + map%map(list(1:nneigh),iu)**2 .lt. map%map(i,iq)**2 + map%map(i, iu)**2 ) .and. all(mask%map(list(1:nneigh), 1) .gt. 0.5) ) then
                rotate_angle = COOP_POLAR_ANGLE(map%map(i, iq), map%map(i, iu))/2.
                call pix2ang_nest(map%nside, i, theta, phi)
                write(fp%unit, "(3E16.7)") theta, phi, rotate_angle
             endif
          else
             if( map%map(i, iq)**2 + map%map(i, iu)**2 .lt. fcut) cycle
             call neighbours_nest(map%nside, i, list, nneigh)  
             if( all( map%map(list(1:nneigh), iq)**2 + map%map(list(1:nneigh), iu)**2 .lt. map%map(i, iq)**2 + map%map(i, iu)**2 ) )then
                rotate_angle = COOP_POLAR_ANGLE(map%map(i, iq), map%map(i, iu))/2.
                call pix2ang_nest(map%nside, i, theta, phi)
                write(fp%unit, "(3E16.7)") theta, phi, rotate_angle
             endif
          endif
       enddo
    case("Pmin", "PTmin")
       select case(map%nmaps)
       case(2:3)
          iq = map%nmaps - 1
          iu = iq + 1
       case default
          stop "For polarization you need to specify Q, U maps in the input file."
       end select
       if(present(threshold))then
          fcut = threshold**2*(sum(map%map(:, iq)**2+map%map(:, iu)**2)/total_weight)
       else
          fcut = 1.d30
       endif
       do i=0, map%npix-1
          if(do_mask)then
             if(map%map(i,iq)**2 + map%map(i,iu)**2 .gt. fcut .or. mask%map(i, 1) .le. 0.5 ) cycle
             call neighbours_nest(map%nside, i, list, nneigh)  
             if(all(map%map(list(1:nneigh), iq)**2 + map%map(list(1:nneigh), iu)**2 .gt. map%map(i, iq)**2 + map%map(i, iu)**2) .and. all(mask%map(list(1:nneigh), 1) .gt. 0.5) ) then
                rotate_angle = COOP_POLAR_ANGLE(map%map(i,iq), map%map(i,iu))/2.
                call pix2ang_nest(map%nside, i, theta, phi)
                write(fp%unit, "(3E16.7)") theta, phi, rotate_angle
             endif
          else
             if(map%map(i, iq)**2 + map%map(i, iu)**2 .gt. fcut) cycle
             call neighbours_nest(map%nside, i, list, nneigh)  
             if(all(map%map(list(1:nneigh), iq)**2 + map%map(list(1:nneigh), iu)**2 .gt. map%map(i, iq)**2 + map%map(i, iu)**2))then
                rotate_angle = COOP_POLAR_ANGLE(map%map(i, iq), map%map(i, iu))/2.
                call pix2ang_nest(map%nside, i, theta, phi)
                write(fp%unit, "(3E16.7)") theta, phi, rotate_angle
             endif
          endif
       enddo
    case default
       write(*,*) trim(spot_type)
       stop "unknown spot type"
    end select
    call map%free
    call mask%free
    call fp%close()
  end subroutine coop_healpix_export_spots


  subroutine coop_healpix_output_map(map, header, fname)
    real(sp), dimension(:,:):: map
    character(LEN=80),dimension(:):: header
    COOP_UNKNOWN_STRING fname
    call coop_delete_file(trim(fname))
    call output_map(map, header, fname)
  end subroutine coop_healpix_output_map
  
  subroutine coop_healpix_mask_map(mapfile, maskfile, output, index_list)
    type(coop_healpix_maps) map, mask
    integer i
    COOP_UNKNOWN_STRING mapfile, maskfile, output
    integer,dimension(:),optional::index_list
    call map%read(mapfile)
    call mask%read(maskfile,  nmaps_wanted = 1)
    if(mask%ordering .eq. COOP_RING)then
       call map%convert2ring()
    elseif(mask%ordering .eq. COOP_NESTED)then
       call map%convert2nested()
    else
       write(*,*) "coop_healpix_mask_map: mask file has unknown ordering."
       stop
    endif
    call coop_delete_file(output)
    if(present(index_list))then
       if(any(index_list .lt. 1 .or. index_list .gt. map%nmaps)) stop "coop_healpix_write_map: index out of range"
       do i=1, size(index_list)
          map%map(:,index_list(i)) = map%map(:, index_list(i))*mask%map(:,1)
       enddo
       call map%write(trim(coop_file_add_postfix(output,"_masked")), index_list)
       call map%write(output)
    else
       do i=1, map%nmaps
          map%map(:,i) = map%map(:, i)*mask%map(:,1)
       enddo
       call map%write(output)
    endif
    call map%free
    call mask%free
  end subroutine coop_healpix_mask_map




  subroutine coop_healpix_smooth_maskfile(mask_file, smoothscale, output)
    COOP_UNKNOWN_STRING mask_file
    real(sp) smoothscale
    COOP_UNKNOWN_STRING, optional::output
    type(coop_healpix_maps) this
    call this%read(mask_file, nmaps_wanted = 1)
    call this%smooth_mask( smoothscale)
    if(present(output))then
       call this%write(trim(output))
    else
       call this%write(trim(coop_file_add_postfix(trim(mask_file), "_smoothed")))
    endif
    call this%free
  end subroutine coop_healpix_smooth_maskfile

  subroutine coop_healpix_smooth_mask(this, smoothscale)
    real(sp),parameter::nefolds = 4
    class(coop_healpix_maps) this
    type(coop_healpix_maps) hgs
    integer,dimension(:),allocatable::listpix
    integer i, j, nsteps
    real(sp) smoothscale, decay
    nsteps = ceiling(smoothscale*this%nside*nefolds/2.)
    if(nsteps .le. 0 .or. nsteps .gt. 200)stop "coop_healpix_smooth_mask: invalid input of smoothscale"
    decay = exp(-nefolds/nsteps/2.)
    call this%convert2nested()
    this%mask_npix = count(this%map(:,1) .lt. 1.)
    allocate(this%mask_listpix(this%mask_npix))
    j = 0
    do i = 0, this%npix - 1
       if(this%map(i,1).lt. 1.)then
          j = j + 1
          this%mask_listpix(j) = i
       endif
    enddo
    select type(this)
    type is (coop_healpix_maps)
       hgs = this
    class default
       stop "the mask must be basic coop_healpix_maps type"
    end select
    do i=1, nsteps
       call coop_healpix_iterate_mask(this, hgs, decay)
       call coop_healpix_iterate_mask(hgs, this, decay)
    enddo
    call hgs%free
    call this%convert2ring()
  contains 
    subroutine coop_healpix_iterate_mask(this_from, this_to, decay)  
      type(coop_healpix_maps) this_from, this_to
      integer list(8), nneigh
      integer i
      real(sp) decay
      !$omp parallel do private(list, nneigh, i)
      do i = 1, this%mask_npix
         call neighbours_nest(this_from%nside, this%mask_listpix(i), list, nneigh)
         this_to%map(this_from%mask_listpix(i), 1) = max(maxval(this_from%map(list(1:nneigh), 1)) * decay , this_from%map(this_from%mask_listpix(i), 1))
      enddo
      !$omp end parallel do
    end subroutine coop_healpix_iterate_mask
  end subroutine coop_healpix_smooth_mask

  subroutine coop_healpix_lowpass_mask(map, mask, polmask, fwhm)
    real(dl) fwhm, sigma, s2
    integer lmax, l
    type(coop_healpix_maps)::map, mask, tmp
    type(coop_healpix_maps),optional::polmask
    sigma = fwhm * coop_sigma_by_fwhm
    lmax = min(map%nside*2, floor(3.d0/sigma))
    tmp = map
    where(mask%map(:,1).eq.0.)
       tmp%map(:,1) = 0.
    end where
    if(present(polmask))then
       if(map%nmaps .lt. 3) stop "Error in lowpass_mask: for nmaps<3 you cannot use polmask"
       where(polmask%map(:,1).eq.0.)
          tmp%map(:,2) = 0.
          tmp%map(:,3) = 0.
       end where
    endif
    call tmp%map2alm(lmax)
    s2 = sigma**2/2.d0
    do l=0, lmax
       tmp%alm(l,:,:) = tmp%alm(l,:,:)*exp(-l*(l+1.d0)*s2)
    enddo
    call tmp%alm2map()
    where(mask%map(:,1).eq.0.)
       map%map(:,1) = tmp%map(:,1)
    end where
    if(present(polmask))then
       where(polmask%map(:,1).eq.0.)
          map%map(:,2) = tmp%map(:,2)
          map%map(:,3) = tmp%map(:,3)
       end where
    endif
    call tmp%free()
  end subroutine coop_healpix_lowpass_mask



  subroutine coop_healpix_inpainting(mode, map_file, mask_file, maskpol_file, output_freq, output_types, mask_smooth_scale)
    COOP_UNKNOWN_STRING map_file, mask_file, mode
    integer, optional::output_freq 
    COOP_UNKNOWN_STRING,optional:: maskpol_file, output_types
    integer,parameter:: total_steps = 1000, burnin = 20
    integer output_steps 
    integer step, naccept, weight
    logical accept
    type(coop_healpix_maps) map, simumap, mask, maskpol, mapmean, tebmap
    COOP_SHORT_STRING::ot
    real(dl) prev_chisq
    real(dl), optional:: mask_smooth_scale
    real(sp)::mss
    if(present(mask_smooth_scale))then
       mss = mask_smooth_scale
    else
       mss = 2.*coop_SI_degree
    endif
    if(present(output_freq))then
       output_steps = output_freq
    else
       output_steps = 50
    endif
    if(present(output_types))then
       ot = trim(output_types)
    else
       ot = "IQU"
    end if
    if(trim(mode) .eq. "I")then
       call map%read(map_file, nmaps_wanted = 1)
    else
       call map%read(map_file, nmaps_wanted = 3)
    endif
    mapmean = map   
    mapmean%map = 0
    call mask%read(mask_file, nmaps_wanted = 1)
    if(present(maskpol_file)) then
       call maskpol%read(maskpol_file, nmaps_wanted = 1)
       call coop_healpix_LowPass_mask(map, mask, maskpol, fwhm = coop_healpix_inpaiting_lowpass_fwhm)
       call coop_healpix_smooth_mask(maskpol, mss)
       map%maskpol_npix = floor(map%npix - sum(maskpol%map(:,1)))
    else
       map%maskpol_npix = 0
       call coop_healpix_LowPass_mask(map, mask, fwhm =coop_healpix_inpaiting_lowpass_fwhm)
    endif
    call coop_healpix_smooth_mask(mask, mss)
    map%mask_npix = floor(map%npix - sum(mask%map(:,1)))
    call coop_healpix_inpainting_init(map, simumap)
    prev_chisq = map%chisq
    naccept = 0
    weight = 0
    step = 0
    do while(step .lt. total_steps)
       step = step + 1
       if(present(maskpol_file))then
          call coop_healpix_inpainting_step(accept, map, simumap, mask, maskpol)
       else
          call coop_healpix_inpainting_step(accept, map, simumap, mask)
       endif
       if(accept) naccept = naccept + 1
       if(naccept .eq. burnin/2 .and. accept)then
          map%Cl = simumap%Cl
       endif
       if(naccept .ge. burnin)then
          mapmean%map = mapmean%map + map%map
          if(weight.eq.0)then
             write(*,*) "initial trials done: now start sampling"
             step = 0
          endif
          weight = weight + 1
       endif
       write(*, "(I6, A)") step, " accept = "//trim(coop_num2str(accept))//" temperature = "//trim(coop_num2str(map%mcmc_temperature,"(F10.2)"))//" chisq = "//trim(coop_num2str(prev_chisq, "(G14.3)"))//" --> "//trim(coop_num2str(map%chisq, "(G14.3)"))
       prev_chisq = map%chisq
       
       if(mod(step, output_steps) .eq.0 )then
          select case(ot)
          case("", "IQU")
             call map%write(trim(coop_file_add_postfix(trim(map_file), "_inp"//trim(coop_ndigits(step, 4)))))         
          case("TEB")
             tebmap = map
             call tebmap%iqu2TEB()
             call tebmap%write(trim(coop_file_add_postfix(trim(map_file), "_inp_teb"//trim(coop_ndigits(step, 4))))) 
          case default
             write(*,*) trim(ot)
             stop "Unknown output types"
          end select
       endif
       if(mod(step, output_steps*10) .eq. 0)then !!less mean maps to save disk space
          simumap%map =  mapmean%map/weight
          call simumap%write(trim(coop_file_add_postfix(trim(map_file), "_inp_mean"//trim(coop_ndigits(step, 4)))))
       endif
    enddo
    call map%free()
    call mapmean%free()
    call simumap%free()
    call mask%free()
    call maskpol%free()
    call tebmap%free()
  end subroutine coop_healpix_inpainting

  subroutine coop_healpix_inpainting_init(map, simumap)
    type(coop_healpix_maps) map, simumap,tmpmap
    call map%map2alm()
    map%cl(0:1, :) = 0.
    map%cl(:, coop_healpix_index_TT) = max(map%cl(:, coop_healpix_index_TT), 1.e-8)*(map%npix/real(map%npix - map%mask_npix))
    if(map%nmaps.ge.3)then
       map%cl(:, coop_healpix_index_EE) = max(map%cl(:, coop_healpix_index_EE), 1.e-10)*(map%npix/real(map%npix-map%maskpol_npix))
       map%cl(:, coop_healpix_index_TE) = map%cl(:, coop_healpix_index_TE)*sqrt((map%npix/real(map%npix-map%maskpol_npix))*(map%npix/real(map%npix-map%mask_npix))*0.999999) !!0.999999 is to avoid 0 determinant
       map%cl(:, coop_healpix_index_BB) = max(map%cl(:, coop_healpix_index_BB), 1.e-12)*(map%npix/real(map%npix-map%maskpol_npix))

       map%cl(:, coop_healpix_index_EB) = 0. 
       map%Cl(:, coop_healpix_index_TB) = 0.
    endif
    map%Cl(0:1,:) = 0.
    map%mcmc_temperature = 20.     !!start with a high temperature
    coop_healpix_inpainting_lowl = 5
    simumap = map
    call coop_healpix_inpainting_get_chisq(map, simumap)

    map%chisq = simumap%chisq
  end subroutine coop_healpix_inpainting_init
  
  subroutine coop_healpix_inpainting_step(accept, map, simumap, mask, maskpol)
    type(coop_healpix_maps) map, simumap, mask
    type(coop_healpix_maps),optional::maskpol
    logical accept
    integer i
    simumap%Cl = map%Cl
    call simumap%simulate()
    call simumap%write("simulated_w_map.fits")
    simumap%map(:,1) =  map%map(:,1) * mask%map(:,1) + simumap%map(:,1) * sqrt(1.-mask%map(:,1)**2)
    call simumap%write("simulated_w_map.fits")
    if(map%nmaps.eq.3)then
       if(present(maskpol))then
          simumap%map(:,2) =  map%map(:,2) * maskpol%map(:,1) + simumap%map(:,2) * sqrt(1.-maskpol%map(:,1)**2)
          simumap%map(:,3) =  map%map(:,3) * maskpol%map(:,1) + simumap%map(:,3) * sqrt(1.-maskpol%map(:,1)**2)
       else
          stop "coop_healpix_inpainting_step: need polarization mask"
       endif
    endif
    call coop_healpix_inpainting_accept_reject(accept, map, simumap)
  end subroutine coop_healpix_inpainting_step


  subroutine coop_healpix_inpainting_get_chisq(map, simumap)
    type(coop_healpix_maps) map, simumap
    integer l
    real(sp) chisq
    call simumap%map2alm()
    if(map%nmaps .eq. 1)then
       chisq = 0.
       !$omp parallel do reduction(+:chisq)
       do l = 2, coop_healpix_inpainting_lowl 
          chisq = chisq + (2*l+1)*(simumap%Cl(l,1)/map%Cl(l,1) - log(simumap%Cl(l,1)/map%Cl(l,1))-1.d0)
       enddo
       !$omp end parallel do
       simumap%chisq = chisq 

    else
       chisq = 0.
       !$omp parallel do reduction(+:chisq)
       do l = 2, coop_healpix_inpainting_lowl 
          chisq = chisq + (2*l+1)*(simumap%Cl(l,coop_healpix_index_BB)/map%Cl(l,coop_healpix_index_BB) - log(simumap%Cl(l,coop_healpix_index_BB)/map%Cl(l,coop_healpix_index_BB))-3.d0 - log((simumap%Cl(l, coop_healpix_index_TT)*simumap%Cl(l, coop_healpix_index_EE) - simumap%Cl(l, coop_healpix_index_TE)**2)/(map%Cl(l, coop_healpix_index_TT)*map%Cl(l, coop_healpix_index_EE) - map%Cl(l, coop_healpix_index_TE)**2)) + (map%Cl(l, coop_healpix_index_TT)*simumap%Cl(l, coop_healpix_index_EE) + simumap%Cl(l, coop_healpix_index_TT)*map%Cl(l, coop_healpix_index_EE) - 2.*map%Cl(l, coop_healpix_index_TE)*simumap%Cl(l, coop_healpix_index_TE) )/(map%Cl(l, coop_healpix_index_TT)*map%Cl(l, coop_healpix_index_EE) - map%Cl(l, coop_healpix_index_TE)**2))
       enddo
       !$omp end parallel do
       simumap%chisq = chisq 
    endif
  end subroutine coop_healpix_inpainting_get_chisq

  subroutine coop_healpix_inpainting_accept_reject(accept, map, simumap)
    type(coop_healpix_maps) map, simumap
    logical accept
    call coop_healpix_inpainting_get_chisq(map, simumap)
    if(simumap%chisq - map%chisq .lt. coop_random_exp()*2*map%mcmc_temperature)then
       accept = .true.
       map%chisq = simumap%chisq
       map%map = simumap%map

       map%alm = simumap%alm
       map%mcmc_temperature = max(1., map%mcmc_temperature*0.95)
       coop_healpix_inpainting_lowl = min(coop_inpainting_lowl_max, coop_healpix_inpainting_lowl + 1)
    else
       accept = .false.
       map%mcmc_temperature = map%mcmc_temperature*1.01
       coop_healpix_inpainting_lowl = max(coop_inpainting_lowl_min, coop_healpix_inpainting_lowl - 1)
    endif
  end subroutine coop_healpix_inpainting_accept_reject


  subroutine coop_healpix_split(filename)
    COOP_UNKNOWN_STRING:: filename
    type(coop_healpix_maps) this
    integer i
    call this%read(filename)
    do i=1, this%nmaps
       call this%write(trim(coop_file_add_postfix(filename, "_submap"//trim(coop_ndigits(i, 3)))), (/ i /) )
    enddo
    call this%free()
  end subroutine coop_healpix_split

  subroutine coop_healpix_plot_spots(spotsfile, mapfile)
    COOP_UNKNOWN_STRING spotsfile, mapfile
    type(coop_file) fp
    real(dl) theta, phi, angle_rotate
    integer pix
    type(coop_healpix_maps) this
    call this%init(64, 1, (/ 0 /) )
    this%map = 0
    call fp%open(trim(spotsfile), "r")
    do
       read(fp%unit, *, END=100, ERR=100) theta, phi, angle_rotate
       call ang2pix_ring(this%nside, theta, phi, pix)
       this%map(pix, 1) = 1.d0
    enddo
100 call fp%close()
    call this%write(trim(mapfile))
    call this%free
  end subroutine coop_healpix_plot_spots

end module coop_healpix_mod