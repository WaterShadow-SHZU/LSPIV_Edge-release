!! This file is part of Image_Velocimetry_Solver, a fortran solver for image velocimetry.
!!
!! Copyright (C) 2022 INRAE
!!
!! Image_Velocimetry_Solver is free software; you can redistribute it and/or
!! modify it under the terms of the GNU Lesser General Public
!! License as published by the Free Software Foundation; either
!! version 3 of the License, or (at your option) any later version.
!!
!! Alternatively, you can redistribute it and/or
!! modify it under the terms of the GNU General Public License as
!! published by the Free Software Foundation; either version 2 of
!! the License, or (at your option) any later version.
!!
!! Image_Velocimetry_Solver is distributed in the hope that it will be useful, but
!! WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
!! FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License
!! or the GNU General Public License for more details.
!!
!! You should have received a copy of the GNU Lesser General Public
!! License and a copy of the GNU General Public License along with
!! Image_Velocimetry_Solver If not, see <http://www.gnu.org/licenses/>.

module mod_PIV

   use iso_fortran_env, only: error_unit
   use lspiv_parameter, only: dp

   contains

subroutine sub_PIV(image1, image2, out_file, Bi, Bj, Sim, Sjm, Sip, Sjp, R_min, R_max, ni, nj, compt, x, y, ncore)

!     PIV analysis of a sequence of images, using CDWS with sub-pixel
!     gaussian fit.
!
! the directive openmp2 allows to choose between sequential and parallel version
! sequential version must be used with FlowPic solver and parallel version can be used for Fudaa-LSPIV solver
#ifndef openmp2
   use omp_lib
#endif /* openmp2 */

   implicit none

   ! -- prototype --
   character (len=*), intent(in) :: image1, image2, out_file  ! filenames
   integer, intent(in)           :: Bi, Bj                    ! IA size
   integer, intent(in)           :: Sim, Sjm, Sip, Sjp        ! SA size
   integer, intent(in)           :: ni, nj                    ! images size
   integer, intent(in)           :: compt, x(:), y(:)
   real(kind=dp), intent(in)     :: R_min, R_max
   integer                       :: ncore
   ! -- local variables --
   integer                    :: imax, jmax, i, j, k, l, m, n, Bi2, Bj2, BiBj
   real(kind=dp)              :: sum_ia, sum_ib, sum_t1, sum_t2, sum_t3, dm, dn
   integer, allocatable       :: imga(:,:), imgb(:,:), ia(:), ib(:), peak_size(:)
   real(kind=dp), allocatable :: c(:,:), ria(:), rib(:), cmax(:), rimax(:), rjmax(:)
   logical, allocatable       :: is_in(:,:)
   integer                    :: lu, lw, ios
   character(len=10)          :: ligne
   !  -- ecart type --
   real(kind=dp), allocatable :: sigma_m(:), sigma_n(:)
   real(kind=dp)              :: esperance_m, esperance_n, summ_c
   integer, allocatable       :: aire(:)

   !---initializing
   if (ncore < 1) ncore = 1
   Bj2 = (Bj-1)/2  ;  Bi2 = (Bi-1)/2  ;  BiBj = Bi*Bj
   allocate(ia(BiBj), ib(BiBj), c(Sim+Sip+1,Sjm+Sjp+1), imga(ni,nj), imgb(ni,nj), ria(BiBj), rib(BiBj))
   c(:,:) = 0.0001_dp
   allocate(is_in(Sim+Sip+1,Sjm+Sjp+1))

   !---Read the 2 images used
   ! Both readers accept P2 (ASCII) and P5 (binary). The ASCII path is kept for
   ! backwards compatibility with existing image sets; the binary path is what
   ! the pipeline produces now, because parsing 640k ASCII numbers per image
   ! cost about 40 ms of the ~140 ms each pair used to take.
   call read_pgm_any(image1, imga, ni, nj, ios)
   if (ios /= 0) then
      write(*,'(a)') 'ERROR sub_PIV : cannot read '//trim(image1)
      return
   endif
   call read_pgm_any(image2, imgb, ni, nj, ios)
   if (ios /= 0) then
      write(*,'(a)') 'ERROR sub_PIV : cannot read '//trim(image2)
      return
   endif

   !---PIV analysis
   allocate(cmax(compt),rimax(compt),rjmax(compt))
   allocate(sigma_m(compt), sigma_n(compt), aire(compt), peak_size(compt))
   rimax(1:compt) = 0._dp  ;  rjmax(1:compt) = 0._dp  ;  cmax(1:compt) = -99._dp
   peak_size(1:compt) = 0
   ! These three are statistics of the correlation surface around one grid
   ! point. They used to be initialised once, before the grid loop, and then
   ! accumulated across every point that followed, so every point except the
   ! first divided its weighted sums by a running total that also contained the
   ! previous points. Resetting them per point is what makes the sigma columns
   ! (6 and 7) reproducible.
   !
   ! sigma_m, sigma_n and aire are only written inside the boundary check below.
   ! Giving them a defined value up front stops the points that fail that check
   ! from writing whatever the allocator happened to leave in memory into
   ! vel_raw/piv.dat (columns 6-8) - which is also why those columns used to
   ! differ between runs of the very same input.
   sigma_m(1:compt) = 0._dp  ;  sigma_n(1:compt) = 0._dp  ;  aire(1:compt) = 0
   imax = -1  ;  jmax = -1

!When used by FlowPic solver openmp2 must be defined to avoid parallelization here
#ifndef openmp2
!$omp parallel default(private) shared(compt,x,y,cmax,rimax,rjmax,sigma_m,sigma_n,aire,peak_size) &
      !$omp shared(Bj2,Bi2,Sim,Sjm,Sip,Sjp,Bi,Bj,imga,imgb,BiBj,ni,nj,R_min,R_max) &
      !$omp num_threads(ncore)
!$omp do schedule(static,compt/omp_get_num_threads())
#endif /* openmp2 */
   do i = 1, compt
      if ( (x(i)-Bj2 > Sjm)  .and. (y(i)-Bi2 > Sim) .and. (x(i)+Bj2+Sjp < nj) .and. (y(i)+Bi2+Sip < ni) ) then
         ! Reset the correlation-surface accumulators for this grid point. They
         ! are private per thread under OpenMP, so carrying a value in from the
         ! previous point makes the sigma columns depend on the thread count.
         esperance_m = 0._dp  ;  esperance_n = 0._dp  ;  summ_c = 0._dp
         cmax(i) = -99._dp
         j = 0 ; do l = x(i)-Bj2, x(i)+Bj2
            do k = y(i)-Bi2, y(i)+Bi2
               j = j+1
               ia(j) = imga(k+1,l+1)
            enddo
         enddo
         ! Pre-computation for mean and deviation of patch A
         sum_ia = sum(ia)/real(BiBj,kind=dp)
         ria(:) = ia(:) - sum_ia
         sum_t2 = dot_product(ria,ria)

         do m = 0, Sjm+Sjp     ! Run over Searching Area
            do n = 0, Sim+Sip
               ! Extract patch B
               j= 0 ; do l = x(i)-Sjm+m-Bj2, x(i)-Sjm+m+Bj2
                  do k = y(i)-Sim+n-Bi2, y(i)-Sim+n+Bi2
                     j = j+1
                     ib(j) = imgb(k+1,l+1)
                  enddo
               enddo
               ! Pre-computation for patch B
               sum_ib = sum(ib)/real(BiBj,kind=dp)
               rib(:) = ib(:) - sum_ib
               sum_t1 = dot_product(ria,rib)
               sum_t3 = dot_product(rib,rib)
               ! Compute NCC
               c(n+1,m+1) = max(sum_t1/(sqrt(sum_t2*sum_t3)),0.0)
               ! somme des NCC pour normaliser
               summ_c = summ_c + c(n+1,m+1)
               ! somme ponderee des indices m
               esperance_m = esperance_m + m*c(n+1,m+1)
               ! somme ponderee des indices n
               esperance_n = esperance_n + n*c(n+1,m+1)
               ! Update max location
               if (c(n+1,m+1) > cmax(i)) then
                  cmax(i) = c(n+1,m+1)  ;  imax = n  ;  jmax = m
               endif
            enddo
         enddo
         ! esperance d'etre sur l'indice m
         esperance_m = esperance_m/summ_c
         ! esperance d'etre sur l'indice n
         esperance_n = esperance_n/summ_c
         sigma_m(i) = 0._dp
         sigma_n(i) = 0._dp
         do m = 0, Sjm+Sjp
           do n = 0, Sim+Sip
             ! on divise c par summ_c pour que c/summ_c soir une probabilité
             sigma_m(i) = sigma_m(i) + c(n+1,m+1)*m*m/summ_c
             sigma_n(i) = sigma_n(i) + c(n+1,m+1)*n*n/summ_c
           enddo
         enddo
         ! ecart type selon m (en pixel)
         sigma_m(i) = sqrt(sigma_m(i) - esperance_m*esperance_m)
         ! ecart type selon n (en pixel)
         sigma_n(i) = sqrt(sigma_n(i) - esperance_n*esperance_n)

         ! calcul de l'aire en pixels dans laquelle la correlation est au moins 0.8*c_max
         aire(i) = 0
         do m = 0, Sjm+Sjp
           do n = 0, Sim+Sip
             if (c(n+1,m+1) >= cmax(i)*0.8) then
               aire(i) = aire(i) + 1
             endif
           enddo
         enddo

         ! calcul de l'aire en pixels dans laquelle la correlation est au moins 0.8*cmax mais seulement autour du max
         is_in(:,:) = .false.
         call ff (c, is_in , imax+1, jmax+1, 0.8*cmax(i), peak_size(i))

         ! Gaussian sub-pixel fit
         n = imax+1  ;  m = jmax+1   ! Indexes n and m used for compatibility with Fortran table
         if ((imax > 0) .and. (jmax > 0) .and. (imax < Sim+Sip) .and. (jmax < Sjm+Sjp) .and. (cmax(i)<1)) then
            ! Case 2D Gaussian fit
            dn = 0.5_dp * (log(c(n-1,m))-log(c(n+1,m))) / (log(c(n-1,m))+log(c(n+1,m))-2._dp*log(c(n,m)))
            dm = 0.5_dp * (log(c(n,m-1))-log(c(n,m+1))) / (log(c(n,m-1))+log(c(n,m+1))-2._dp*log(c(n,m)))
         elseif ((imax == 0) .and. (jmax > 0) .and. (jmax < Sjm+Sjp) .and. (cmax(i)<1)) then
            ! Case 1D Gaussian fit
            dm = 0.5_dp * (log(c(n,m-1))-log(c(n,m+1))) / (log(c(n,m-1))+log(c(n,m+1))-2._dp*log(c(n,m)))
            dn = 0._dp
         elseif ((imax > 0) .and. (jmax == 0) .and. (imax < Sim+Sip) .and. (cmax(i)<1)) then
            ! Case 1D Gaussian fit
            dn = 0.5_dp * (log(c(n-1,m))-log(c(n+1,m))) / (log(c(n-1,m))+log(c(n+1,m))-2._dp*log(c(n,m)))
            dm = 0._dp
         else
            ! Case no Gaussian fit
            dm = 0._dp
            dn = 0._dp
         endif
         ! Recover max position
         imax = imax-Sim  ;  jmax = jmax-Sjm

         ! Save results
!         if ((cmax(i) < R_min) .or. (cmax(i) > R_max)) then
!            cmax(i) = 0._dp
!         else
            if (abs(dm) < 1._dp .and. abs(dn) < 1._dp) then
               rimax(i) = imax + dn  ;  rjmax(i) = jmax + dm
               ! Interpolation of c
               if ((n+dn >= 2) .and. (m+dm >= 2) .and. (n < Sim+Sip) .and. (m < Sjm+Sjp))then
                  cmax(i) = cub_conv2d(dn+n,dm+m,n,m,c)
               elseif ((n == 1) .and. (m+dm >= 2) .and. (m < Sjm+Sjp))then
                  cmax(i) = cub_conv1dx(dm+m,n,m,c)
               elseif ((n+dn >= 2) .and. (n < Sim+Sip) .and. (m == 1)) then
                  cmax(i) = cub_conv1dy(dn+n,n,m,c)
               endif
            else
               rimax(i) = imax ;  rjmax(i) = jmax
            endif
!         endif
      endif
   enddo
#ifndef openmp2
!$omp end do
!$omp end parallel
#endif /* openmp2 */

   !---Write output file
   open(newunit=lu,file=trim(out_file),form='formatted',status='unknown')
   do i = 1, compt
      write(lu,*) y(i), x(i), rimax(i), rjmax(i), cmax(i), 100*sigma_n(i)/(Sim+Sip+1),&
      100*sigma_m(i)/(Sjm+Sjp+1), aire(i), peak_size(i)
   enddo
   close(lu)
   deallocate (ia, ib, c, imga, imgb, ria, rib, cmax, rimax, rjmax)
end subroutine sub_PIV

!------------------------------
!!Convolution 1D-y
!------------------------------
function cub_conv1dy(dn,n,m,c)
!Compute the intensity of a pixel using cubic convolution
   implicit none
   real(kind=dp), parameter :: zero=0._dp, un=1._dp, deux=2._dp, four=4._dp
   real(kind=dp), parameter :: cinq=5._dp, huit=8._dp
   ! -- prototype --
   integer, intent(in) :: n, m
   real(kind=dp), intent(in) :: dn, c(:,:)
   real(kind=dp) :: cub_conv1dy
   ! -- variables locales --
   integer :: intN, l
   real(kind=dp) :: sy, Cy, sum_fx

   intN = int(dn)
   sum_fx = 0._dp
   do l = 1, 4
      sy = abs(intN+l-2-dn)
      if ((sy >= zero) .and. (sy < un)) then
         Cy = un + (sy-deux)*sy*sy
      elseif ((sy >= un) .and. (sy < deux)) then
         Cy = four + ((cinq-sy)*sy-huit)*sy
      elseif (sy > deux) then
         Cy = zero
      endif
      sum_fx = sum_fx + c(intN+l-2,m)*Cy
   enddo
   if (sum_fx > un) then
      cub_conv1dy = un
   elseif (sum_fx < zero) then
      cub_conv1dy = zero
   else
      cub_conv1dy = sum_fx
   endif
end function cub_conv1dy

!----------------------------
!Convolution 1D-x
!----------------------------
function cub_conv1dx(dm,n,m,c)
!Compute the intensity of a pixel using cubic convolution
   implicit none
   real(kind=dp), parameter :: zero=0._dp, un=1._dp, deux=2._dp, four=4._dp
   real(kind=dp), parameter :: cinq=5._dp, huit=8._dp
   ! -- prototype --
   integer, intent(in) :: n, m
   real(kind=dp), intent(in) :: dm, c(:,:)
   real(kind=dp) :: cub_conv1dx
   ! -- variables locales --
   integer :: intM, k
   real(kind=dp) :: sx, Cx, sum_fx

   intM = int(dm)
   sum_fx = 0._dp
   do k = 1, 4
      sx = abs(intM+k-2-dm)
      if ((sx >= zero) .and. (sx < un)) then
         Cx = un + (sx-deux)*sx*sx
      elseif ((sx >= un) .and. (sx < deux)) then
         Cx = four + ((cinq-sx)*sx-huit)*sx
      elseif (sx > deux) then
         Cx = zero
      endif
      sum_fx = sum_fx + c(n,intM+k-2)*Cx
   enddo

   if (sum_fx > un) then
      cub_conv1dx = un
   elseif (sum_fx < zero) then
      cub_conv1dx = zero
   else
      cub_conv1dx = sum_fx
   endif
end function cub_conv1dx

!--------------------------------
!! Convolution 2D
!--------------------------------
function cub_conv2d(dn,dm,n,m,c)
!Compute the intensity of a pixel using cubic convolution
   implicit none
   real(kind=dp), parameter :: zero=0._dp, un=1._dp, deux=2._dp, four=4._dp
   real(kind=dp), parameter :: cinq=5._dp, huit=8._dp
   ! -- prototype --
   real(kind=dp) :: cub_conv2d
   integer, intent(in) :: n, m
   real(kind=dp), intent(in) :: dn, dm, c(:,:)
   integer :: intN, intM, k, l
   real(kind=dp) :: sx, sy, Cx, Cy, sum_fx

   intN = int(dn)
   intM = int(dm)

   sum_fx = 0._dp
   do k = 1, 4
      do l = 1, 4
         sx = abs(intM+k-2-dm)
         if ((sx >= zero) .and. (sx < un)) then
            Cx = un + (sx-deux)*sx*sx
         elseif ((sx >= un) .and. (sx < deux)) then
            Cx = four + ((cinq-sx)*sx-huit)*sx
         elseif (sx > deux) then
            Cx = zero
         endif

         sy = abs(intN+l-2-dn)
         if ((sy >= zero) .and. (sy < un)) then
            Cy = un + (sy-deux)*sy*sy
         elseif ((sy >= un) .and. (sy < deux)) then
            Cy = four + ((cinq-sy)*sy-huit)*sy
         elseif (sy > deux) then
            Cy = zero
         endif

         sum_fx = sum_fx + c(intN+l-2,intM+k-2)*Cx*Cy
      enddo
   enddo
   if (sum_fx > un) then
      cub_conv2d = un
   elseif (sum_fx < zero) then
      cub_conv2d = zero
   else
      cub_conv2d = sum_fx
   endif
end function cub_conv2d

!--------------------------------
! flood fill function
! values : tableau des valeurs à tester
! is_in : masque de même taille que values
! i, j : coordonnées du point de départ
! c : critère à vérifier pour être dans la zone
! n : compteur, incrémenté si (i,j) est dans la zone
!--------------------------------
recursive subroutine ff(values, is_in, i, j, c, n)
  implicit none
  real(kind=dp), dimension(:,:), intent(inout) :: values
  logical, dimension(:,:), intent(inout) :: is_in
  integer, intent(in) :: i, j
  real(kind=dp), intent(in) :: c
  integer, intent(inout) :: n

  if(is_in(i,j)) return ! déjà dedans
  if(values(i,j) < c) return ! pas dedans
  n = n+1 ! dedans
  is_in(i,j) = .true.
  if(i<size(is_in(:,j))) call ff(values, is_in, i+1, j, c, n)
  if(i>1) call ff(values, is_in, i-1, j, c, n)
  if(j<size(is_in(i,:)))call ff(values, is_in, i, j+1, c, n)
  if(j>1)call ff(values, is_in, i, j-1, c, n)
end subroutine ff

!--------------------------------------------------------------------
! Unsigned views of 8- and 16-bit sample buffers.
!
! PGM stores samples as unsigned integers. Fortran has no unsigned integer
! kind, and integer(1)/integer(2) are signed, so reinterpreting the raw bytes
! directly turns any sample >= 128 (or >= 32768) negative. These functions do
! the two's-complement conversion via the bit pattern, which is exactly what
! the format means and is portable across compilers.
!--------------------------------------------------------------------
pure integer function unsigned8(v)
  implicit none
  integer(1), intent(in) :: v
  unsigned8 = iand(int(v, kind=4), 255)
end function unsigned8

pure integer function unsigned16(v)
  implicit none
  integer(2), intent(in) :: v
  unsigned16 = iand(int(v, kind=4), 65535)
end function unsigned16

!--------------------------------------------------------------------
! Read a PGM image, accepting both binary (P5) and ASCII (P2) payloads.
!
! The P5 path is why this exists: the pipeline writes binary frames now, and
! reading 643k raw bytes is a memcpy instead of 643k separate text->number
! conversions. On the reference machine that removes roughly 75 ms from every
! image pair, which is the single largest saving available in this solver.
!
! The header is parsed token by token because PGM allows comments and any
! amount of whitespace between the magic number, the dimensions and maxval.
! For P5 the pixel data starts at the first byte after the maxval token, which
! is NOT necessarily a newline - a reader that skips to the next line would
! silently shift the image by a row on files written that way.
!--------------------------------------------------------------------
subroutine read_pgm_any(filename, img, ni, nj, ios)
  implicit none
  ! -- prototype --
  character(len=*), intent(in) :: filename
  integer, intent(in) :: ni, nj
  integer, intent(out) :: img(:,:)
  integer, intent(out) :: ios
  ! -- local variables --
  integer :: lu, i, j, k, width, height, maxval, token
  integer :: header(3)
  character(len=2) :: magic
  character(len=1) :: ch
  logical :: in_comment
  integer(1), allocatable :: buf8(:)
  integer(2), allocatable :: buf16(:)

  ios = 0
  img = 0
  open(newunit=lu, file=trim(filename), status='old', access='stream', &
       form='unformatted', iostat=ios)
  if (ios /= 0) return

  ! --- magic number ---
  read(lu, iostat=ios) magic
  if (ios /= 0) then
     close(lu) ; return
  endif
  if (magic /= 'P5' .and. magic /= 'P2') then
     ios = 1 ; close(lu) ; return
  endif

  ! --- three header tokens: width, height, maxval ---
  do token = 1, 3
     call read_pgm_token(lu, header(token), ios)
     if (ios /= 0) then
        close(lu) ; return
     endif
  enddo
  width = header(1) ; height = header(2) ; maxval = header(3)
  if (width /= nj .or. height /= ni) then
     ! The caller already knows the expected geometry; a mismatch here means the
     ! image set does not belong to this calibration, so fail loudly.
     write(*,'(a,i0,a,i0,a,i0,a,i0)') 'ERROR read_pgm_any : ',trim(filename), &
          ' is ',width,'x',height,' but ',nj,'x',ni,' was expected'
     ios = 1 ; close(lu) ; return
  endif

  if (magic == 'P5') then
     ! --- binary payload ---
     if (maxval < 256) then
        allocate(buf8(width*height))
        read(lu, iostat=ios) buf8
        if (ios /= 0) then
           deallocate(buf8) ; close(lu) ; return
        endif
        ! PGM samples are unsigned. Fortran's integer(1) is SIGNED, so a byte of
        ! 178 would arrive as -78 and every pixel above 127 would be wrong. Read
        ! through an unsigned view to get the 0..255 value the format means.
        k = 0
        do j = 1, height
           do i = 1, width
              k = k+1
              img(j,i) = int(unsigned8(buf8(k)))
              if (maxval /= 255) img(j,i) = img(j,i)*255/maxval
           enddo
        enddo
        deallocate(buf8)
     else
        allocate(buf16(width*height))
        read(lu, iostat=ios) buf16
        if (ios /= 0) then
           deallocate(buf16) ; close(lu) ; return
        endif
        ! Same signedness trap one size up: integer(2) is signed too, so 16-bit
        ! samples at or above 32768 need the unsigned view as well.
        k = 0
        do j = 1, height
           do i = 1, width
              k = k+1
              img(j,i) = int(unsigned16(buf16(k)))*255/maxval
           enddo
        enddo
        deallocate(buf16)
     endif
  else
     ! --- ASCII payload: one number per pixel, row major ---
     do j = 1, height
        do i = 1, width
           call read_pgm_token(lu, k, ios)
           if (ios /= 0) then
              close(lu) ; return
           endif
           if (maxval == 255) then
              img(j,i) = k
           else
              img(j,i) = k*255/maxval
           endif
        enddo
     enddo
  endif

  close(lu)
end subroutine read_pgm_any

!--------------------------------------------------------------------
! Read the next whitespace-delimited integer in a PGM header/body,
! skipping '#' comments. Operates on a stream-access unit so that the
! byte position after the call is exactly where the P5 payload begins.
!--------------------------------------------------------------------
subroutine read_pgm_token(lu, value, ios)
  implicit none
  integer, intent(in) :: lu
  integer, intent(out) :: value
  integer, intent(out) :: ios
  character(len=1) :: ch
  character(len=24) :: digits
  integer :: nd

  ios = 0
  value = 0
  nd = 0

  ! skip whitespace and comments
  do
     read(lu, iostat=ios) ch
     if (ios /= 0) return
     if (ch == '#') then
        do
           read(lu, iostat=ios) ch
           if (ios /= 0) return
           if (ch == achar(10)) exit
        enddo
     elseif (ch /= ' ' .and. ch /= achar(9) .and. ch /= achar(10) .and. ch /= achar(13)) then
        exit
     endif
  enddo

  ! collect digits
  do
     if (ch >= '0' .and. ch <= '9') then
        nd = nd+1
        if (nd > len(digits)) then
           ios = 1 ; return
        endif
        digits(nd:nd) = ch
        read(lu, iostat=ios) ch
        if (ios /= 0) exit  ! EOF terminates the last token cleanly
     else
        exit
     endif
  enddo
  if (nd == 0) then
     ios = 1 ; return
  endif
  read(digits(1:nd), '(i24)', iostat=ios) value
end subroutine read_pgm_token

end module mod_PIV
