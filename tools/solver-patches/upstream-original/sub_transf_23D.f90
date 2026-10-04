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

module mod_transf_23D

   use iso_fortran_env, only: error_unit, output_unit
   use lspiv_parameter, only: dp, average_vel, filters

   procedure(read_PGM_P2_standard), pointer :: read_PGM_P2 => null()

   contains

subroutine read_PGM_P2_standard(image,img,ni,nj,istop)
! read the raw PGM P2 image, return the table img
! image data are defined by one record per image row
!
!
   implicit none
   ! -- prototype --
   integer, intent(in) :: ni, nj
   character (len=*), intent(in) :: image
   integer, intent(inout) :: img(:,:)
   integer, intent(out) :: istop
   ! -- local variables --
   integer :: lw, nni, nnj, cmax, i, j, ios
   character(len=2) :: p2
   character(len=180) :: err_message

   img = 0
   err_message = 'read_PGM_P2() : Reading file '//trim(image)
   istop = 0

!Read the raw image
   !write(output_unit,'(a)') trim(err_message)
   open(newunit=lw,file=trim(image),status='old',iostat=ios)
   if (ios > 0) then
      write(output_unit,'(2a)') '>>>> Erreur d''ouverture du fichier ',trim(image)
      istop = 1
      return
   endif
   read(lw,*) p2 ; read(lw,*) nnj, nni ; read(lw,*) cmax
   if (p2 /= 'P2') then
      istop = 1
      write(error_unit,'(3a)') 'ERROR read_PGM_P2() : File ',trim(image),' is not a PGM P2 image'
   elseif (nni /= ni) then
      istop = 1
      write(error_unit,'(3a,i0,a,i0)') 'ERROR read_PGM_P2() : File ',trim(image),' - ni expected ',ni, ' read ',nni
   elseif (nnj /= nj) then
      istop = 1
      write(error_unit,'(3a,i0,a,i0)') 'ERROR read_PGM_P2() : File ',trim(image),' - nj expected ',nj, ' read ',nnj
   else
      do i = 1, nni
         read(lw,*,iostat=istop,iomsg=err_message) (img(i,j),j=1,nnj)
         if (istop /= 0) then
            write(error_unit,'(a)') trim(err_message)
            exit
         endif
      enddo
   endif
   close(lw)
end subroutine read_PGM_P2_standard


subroutine read_PGM_P2_solver(image,img,ni,nj,istop)
! read the raw PGM P2 image, return the table img
! image data are defined by only one record (1D)
! data need to be rearranged in the 2D array img
   implicit none
   ! -- prototype --
   integer, intent(in) :: ni, nj
   character (len=*), intent(in) :: image
   integer, intent(inout) :: img(:,:)
   integer, intent(out) :: istop
   ! -- local variables --
   integer :: lw, nni, nnj, cmax, i, j, ios, k
   character(len=2) :: p2
   character(len=180) :: err_message
   integer, allocatable :: p_img(:)

   img = 0
   err_message = 'read_PGM_P2() : Reading file '//trim(image)
   istop = 0
   allocate (p_img(ni*nj))

!Read the raw image
   !write(output_unit,'(a)') trim(err_message)
   open(newunit=lw,file=trim(image),status='old',iostat=ios)
   if (ios > 0) then
      write(output_unit,'(2a)') '>>>> Erreur d''ouverture du fichier ',trim(image)
      istop = 1
      return
   endif
   read(lw,*) p2 ; read(lw,*) nnj, nni ; read(lw,*) cmax
   if (p2 /= 'P2') then
      istop = 1
      write(error_unit,'(3a)') 'ERROR read_PGM_P2() : File ',trim(image),' is not a PGM P2 image'
   elseif (nni /= ni) then
      istop = 1
      write(error_unit,'(3a,i0,a,i0)') 'ERROR read_PGM_P2() : File ',trim(image),' - ni expected ',ni, ' read ',nni
   elseif (nnj /= nj) then
      istop = 1
      write(error_unit,'(3a,i0,a,i0)') 'ERROR read_PGM_P2() : File ',trim(image),' - nj expected ',nj, ' read ',nnj
   else
      read(lw,*,iostat=istop,iomsg=err_message) (p_img(j),j=1,nni*nnj)
      if (istop /= 0) then
         write(error_unit,'(a)') trim(err_message)
         return
      endif
      k = 1
      do i = 1, nni
         do j = 1, nnj
            img(i,j) = p_img(k)
            k = k+1
         enddo
      enddo
   endif
   close(lw)
end subroutine read_PGM_P2_solver


subroutine write_PGM_P2(image, maxx, maxy, gg)
! écriture de l'image gg au format PGM P2
   ! -- prototype --
   character(len=*), intent(in) :: image
   integer, intent(in) :: maxx, maxy
   integer, intent(in) :: gg(:,:)
   ! -- variables locales --
   integer :: i, j, lw
   character(len=9) :: format_P2

   open(newunit=lw,file=trim(image),status='unknown',form='formatted')

   write(format_P2,'(A,I5.5,A)') '(',maxx,'I5)'
   write(lw,'(a2)') 'P2'
   write(lw,*) maxx,maxy
   write(lw,'(a3)') '255'
   do i = 1, maxy
      write(lw,format_P2) (gg(j,i),j=1,maxx)
   enddo
   close(lw)
end subroutine write_PGM_P2


subroutine sub_transf_img_2D(a, xmin, ymin, xmax, ymax, r, ni, nj, image_in, image_out, ncpu, istop)
!     From a raw pgm image, compute the ortho-rectified image using
!     the parameters of coeff.dat.
!     2D-case only
!
! the directive openmp2 allows to choose between sequential and parallel version
! sequential version must be used with FlowPic solver and parallel version can be used for Fudaa-LSPIV solver
!
#ifndef openmp2
   use omp_lib
#endif /* openmp2 */
   implicit none
   ! -- prototype --
   real(kind=dp), intent(in) :: a(11), xmin, ymin, xmax, ymax, r
   integer, intent(in) :: ni, nj
   character (len=*), intent(in) :: image_in, image_out
   integer, intent(in) :: ncpu
   integer, intent(out) :: istop
   ! -- local variables --
   integer :: i, j
   integer :: iinf, isup, jinf, jsup, i2max, j2max, maxx, maxy
   integer, allocatable :: img(:,:), gg(:,:)
   real(kind=dp) :: b(9)
   real(kind=dp) :: x, y, ii, jj
   integer :: ncore

   iinf = 2 ; isup = ni-1 ; jinf = 2 ; jsup = nj-1
   if (ncpu < 1) then
      ncore = 1
   else
      ncore = ncpu
   endif

   allocate(img(ni,nj))
   call read_PGM_P2(image_in, img, ni, nj, istop)
   if (istop /= 0) return !reading PGM file failed, nothing else to do!


!Initialize the output matrix gg(i,j)
!! debut modification par JLC le 30/08/2008
   i2max = int((xmax-xmin)/r)+1  ;  j2max = int((ymax-ymin)/r)+1
   allocate (gg(i2max,j2max))
   gg(:,:) = 0

!!! Image transformation : only 2D orthorectification

   b(1) = a(5)-a(8)*a(6);
   b(2) = a(3)*a(8)-a(2);
   b(3) = a(2)*a(6)-a(3)*a(5);
   b(4) = a(7)*a(6)-a(4);
   b(5) = a(1)-a(3)*a(7);
   b(6) = a(3)*a(4)-a(1)*a(6);
   b(7) = a(8)*a(4)-a(7)*a(5);
   b(8) = a(2)*a(7)-a(1)*a(8);
   b(9) = a(1)*a(5)-a(2)*a(4);

   !Compute the ortho-image
!When used by FlowPic solver openmp2 must be defined to avoid parallelization here
#ifndef openmp2
   !$omp parallel default(shared) private(ii,jj,x,y,i,j) num_threads(ncore)
   !$omp do schedule(static,i2max/omp_get_num_threads())
#endif /* openmp2 */
   do i = 1, i2max
      ii = xmin + i*r
      do j= 1, j2max
         jj=ymin + j*r
         !Compute the image coordinates [x,y] from space coordinates [ii,jj]
         !using the parameters b(9)
         call space2CRT2(x,y,b,ii,jj)
         !Only compute the area of interest defined by iinf,isup,jinf,jsup
         if (((x.ge.jinf).and.(x.le.jsup)).and.((y.ge.iinf).and.(y.le.isup))) then
            !Compute the intensity of the pixel using cubic convolution
            gg(i,j) = cub_conv(x,y,img)
         endif
      enddo
   enddo
#ifndef openmp2
   !$omp end do
   !$omp end parallel
#endif /* openmp2 */

   !Write the data in the output file NomOut
   maxx = i2max-1
   maxy = j2max-1
   call write_PGM_P2(image_out, maxx, maxy, gg)
   deallocate (img, gg)
   istop = 0
end subroutine sub_transf_img_2D


subroutine sub_transf_img_3D(a, h, xmin, ymin, xmax, ymax, r, ni, nj, image_in, image_out, ncore, istop)
!     From a raw pgm image, compute the ortho-rectified image using
!     the parameters of coeff.dat.
!     3D-case only
!
! the directive openmp2 allows to choose between sequential and parallel version
! sequential version must be used with FlowPic solver and parallel version can be used for Fudaa-LSPIV solver
!

#ifndef openmp2
   use omp_lib
#endif /* openmp2 */
   implicit none
   ! -- prototype --
   integer, intent(in) :: ni, nj
   real(kind=dp), intent(in) :: a(11), xmin, ymin, xmax, ymax, r, h
   character (len=*), intent(in) :: image_in, image_out
   integer :: ncore
   integer, intent(out) :: istop
   ! -- local variables --
   integer :: i, j
   integer :: iinf, isup, jinf, jsup, i2max, j2max, maxx, maxy
   integer, allocatable :: img(:,:), gg(:,:)
   real(kind=dp) :: x, y, ii, jj, D3

   iinf = 2 ; isup = ni-1 ; jinf = 2 ; jsup = nj-1
   if (ncore < 1) ncore = 1
   allocate(img(ni,nj))
   call read_PGM_P2(image_in,img,ni,nj,istop)
   if (istop /= 0) return !reading PGM file failed, nothing else to do!

   !Initialize the output matrix gg(i,j)
   i2max = int((xmax-xmin)/r)+1  ;  j2max = int((ymax-ymin)/r)+1
   allocate (gg(i2max,j2max))
   gg(:,:) = 0

   !!! Image transformation : 3D orthorectification
   !Definition of the river plan equation: Z=D1X+D2Y+D3
   !   D1=0
   !   D2=0
   D3 = h
!When used by FlowPic solver openmp2 must be defined to avoid parallelization here
#ifndef openmp2
   !$omp parallel default(shared) private(ii,jj,x,y,i,j) num_threads(ncore)
   !$omp do schedule(static,i2max/omp_get_num_threads())
#endif /* openmp2 */
   do i = 1, i2max
      ii = xmin + i*r
      do j= 1, j2max
         jj=ymin + j*r
         !Compute the image coordinates [x,y] from space coordinates [ii,jj]
         !using the parameters a(11)
         call space2CRT(x,y,a,ii,jj,D3)
         !Only compute the area of interest defined by iinf,isup,jinf,jsup
         if (((x.ge.jinf).and.(x.le.jsup)).and.((y.ge.iinf).and.(y.le.isup))) then
            !Compute the intensity of the pixel using cubic convolution
            gg(i,j) = cub_conv(x,y,img)
         endif
      enddo
   enddo
#ifndef openmp2
   !$omp end do
   !$omp end parallel
#endif /* openmp2 */

   !Write the data in the output file NomOut
   maxx = i2max-1
   maxy = j2max-1
   call write_PGM_P2(image_out, maxx, maxy, gg)
   istop = 0
end subroutine sub_transf_img_3D


subroutine sub_transf_img_0(a, xmin, ymin, xmax, ymax, r, ni, nj, image_in, image_out, ncore, istop)
!     From a raw pgm image, compute the ortho-rectified image using
!     the parameters of coeff.dat.
!     2D-case only
!
! the directive openmp2 allows to choose between sequential and parallel version
! sequential version must be used with FlowPic solver and parallel version can be used for Fudaa-LSPIV solver
!
#ifndef openmp2
   use omp_lib
#endif /* openmp2 */
   implicit none
   ! -- prototype --
   integer, intent(in) :: ni, nj
   real(kind=dp), intent(in) :: a(11), xmin, ymin, xmax, ymax, r
   character (len=*), intent(in) :: image_in, image_out
   integer :: ncore
   integer, intent(out) :: istop
   ! -- local variables --
   integer :: i, j, nx, ny
   integer :: iinf, isup, jinf, jsup, i2max, j2max, maxx, maxy
   integer, allocatable :: img(:,:), gg(:,:)
   real(kind=dp) :: x0, y0

   iinf = 2 ; isup = ni-1 ; jinf = 2 ; jsup = nj-1
   if (ncore < 1) ncore = 1
   allocate(img(ni,nj))
   call read_PGM_P2(image_in,img,ni,nj,istop)
   if (istop /= 0) return !reading PGM file failed, nothing else to do!

   !Initialize the output matrix gg(i,j)
   i2max = int((xmax-xmin)/r)+1  ;  j2max = int((ymax-ymin)/r)+1
   allocate (gg(i2max,j2max))
   gg(:,:) = 0

!!!!!!!!!!!!!!!!!!! NO ortho !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   x0 = a(1)
   y0 = a(2)

   !Compute the ortho-image
!When used by FlowPic solver openmp2 must be defined to avoid parallelization here
#ifndef openmp2
   !$omp parallel default(shared) private(nx,ny,i,j) num_threads(ncore)
   !$omp do schedule(static,i2max/omp_get_num_threads())
#endif /* openmp2 */
   do i = 1, i2max
      do j = 1, j2max
         nx = int((xmin - x0)/r) + i
         ny = int(nj - (ymax-y0)/r) + j
         gg(i,j) = img(ny,nx)  !img(nx,ny)
      enddo
   enddo
#ifndef openmp2
   !$omp end do
   !$omp end parallel
#endif /* openmp2 */

   !Write the data in the output file NomOut
   maxx = i2max-1
   maxy = j2max-1
   call write_PGM_P2(image_out, maxx, maxy, gg)
   istop = 0
end subroutine sub_transf_img_0


subroutine space2CRT(xp,yp,a,ii,jj,D3)
!Compute image coordinates from space coordinates using a(11)
   implicit none
   real(kind=dp), intent(in)  :: a(11) , ii, jj, D3
   real(kind=dp), intent(out) :: xp, yp

   xp = (a(1)*ii+a(2)*jj+(a(3)*D3+a(4))) / (a(9)*ii+a(10)*jj+(a(11)*D3+1))
   yp = (a(5)*ii+a(6)*jj+(a(7)*D3+a(8))) / (a(9)*ii+a(10)*jj+(a(11)*D3+1))
end subroutine space2CRT


subroutine space2CRT2(xp,yp,b,ii,jj)
!Compute image coordinates from space coordinates using b(9)
   implicit none
   real(kind=dp), intent(in)  :: b(9), ii, jj
   real(kind=dp), intent(out) :: xp, yp

   xp = (b(1)*ii+b(2)*jj+b(3)) / (b(7)*ii+b(8)*jj+b(9));
   yp = (b(4)*ii+b(5)*jj+b(6)) / (b(7)*ii+b(8)*jj+b(9));
end subroutine space2CRT2


function cub_conv(xp,yp,img)
!Compute the intensity of a pixel using cubic convolution
   implicit none
   real(kind=dp), parameter :: zero=0._dp, un=1._dp, deux=2._dp, four=4._dp
   real(kind=dp), parameter :: cinq = 5._dp, huit=8._dp

   integer :: cub_conv, ggij
   integer, intent(in) :: img(:,:)
   real(kind=dp), intent(in) :: xp, yp
   integer :: nxp, nyp, k, l
   real(kind=dp) :: sx, sy, Cx, Cy, fx, sum_fx

   nxp = int(xp)
   nyp = int(yp)

   sum_fx = 0._dp
   do k = 1, 4
      do l = 1, 4
         sx = abs(nxp+k-2-xp)
         sy = abs(nyp+l-2-yp)
         if ((sx >= zero) .and. (sx < un)) then
            !Cx = un - deux*(sx*sx) + (sx*sx*sx)
            Cx = un + (sx-deux)*sx*sx
         elseif ((sx >= un) .and. (sx < deux)) then
            !Cx = four - huit*sx + cinq*(sx*sx) - (sx*sx*sx)
            Cx = four + ((cinq-sx)*sx-huit)*sx
         elseif (sx > deux) then
            Cx = zero
         endif

         if ((sy >= zero) .and. (sy < un)) then
            !Cy = un - deux*(sy*sy) + (sy*sy*sy)
            Cy = un + (sy-deux)*sy*sy
         elseif ((sy >= un) .and. (sy < deux)) then
            !Cy = four - huit*sy + cinq*(sy*sy) - (sy*sy*sy)
            Cy = four + ((cinq-sy)*sy-huit)*sy
         elseif (sy > deux) then
            Cy = zero
         endif

         fx = img(nyp+l-2,nxp+k-2)*Cx*Cy
         sum_fx = sum_fx+fx
      enddo
   enddo
   ggij = int(sum_fx)
   if (ggij > 255) ggij = 255
   if (ggij < 0) ggij = 0
   cub_conv = ggij
end function cub_conv

end module mod_transf_23D
