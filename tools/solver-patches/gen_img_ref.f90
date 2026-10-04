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

! Solver gen_img_ref

program gen_img_ref
!solver dedicated to writing img_ref.dat file from GRP.dat
!works only with version 2 of GRP.dat
   use iso_fortran_env, only: error_unit, output_unit
   use errors, only: ERR_GRP_FILE_NOT_FOUND, ERR_COMPUTING_COEF, ERR_GRP_FILE_WRONG_HEADER, ERR_NOT_ENOUGH_POINTS_IN_GRP_FILE
   use lspiv_parameter, only: dp, img_ref, GRP, outputs_dir, coeff_dat
   use mod_ortho, only: sub_ortho, estimated_resolution, compute_XY, compute_XY_2D, compute_XY_3D, compute_A_coeff, compute_XY

   implicit none
   !--local variables --
   character(len=21) :: GRP_dat
   character(len=25) :: img_ref_dat
   character(len=23) :: coeff_file
   logical :: bExist
   integer :: lu, nb_points, ix, jy, ios, n, nbc, i, width, height
   real(kind=dp) :: xmin, xmax, ymin, ymax, x, y, z, resolution
   real(kind=dp) :: a1, a2, a3, a4, c1, c2, c3, b1, b2, b3, b4
   real(kind=dp) :: m1, m2, m3, p1, p2 , p3, q1, q2, q3
   real(kind=dp) :: a(9)
   character(len=3) :: ttt
   character(len=4) :: v20
   logical :: bFail

!    include "errors.i"

   img_ref_dat = './'//outputs_dir//'/'//img_ref
   GRP_dat = './'//outputs_dir//'/'//GRP
   coeff_file = './'//outputs_dir//'/'//coeff_dat

   !check if GRP.dat exists
   inquire(file=trim(GRP_dat),exist=bExist)
   if (.not.bExist) then
      write(error_unit,'(3a)') '>>>> ERROR: ',GRP_dat,' file not found'
      stop ERR_GRP_FILE_NOT_FOUND
   endif

   !check if coeff.dat exists. If it does not, then launch sub_ortho()
   inquire(file=trim(coeff_file),exist=bExist)
   if (.not.bExist) then
      call sub_ortho('./'//outputs_dir)
   endif

   call compute_A_coeff(coeff_file,a,nbc)
   select case (nbc)
      case (8) ; compute_XY => compute_XY_2D
      case (11) ; compute_XY => compute_XY_3D
      case default
         write(error_unit,'(a,i0)') '>>>> ERROR computing A coeff ; nbc not equal to 8 or 11 : ',nbc
         stop ERR_COMPUTING_COEF
   end select

   !reading GRP.dat to get xmin, ymin, xmax, ymax
   xmin = 1.e+30_dp  ;  xmax = -1.e+30_dp  ;  ymin = 1.e+30_dp  ;  ymax = -1.e+30_dp
   open(newunit=lu,file=trim(GRP_dat),form='formatted',status='old')
   !reading header GRP V2.0 width height
   bFail = .false.
   read(lu,*,iostat=ios) ttt, v20, width, height
   if (ios /= 0) bFail = .true.
   if (ttt /= 'GRP' .and. ttt /= 'grp') bFail = .true.
   if (v20 /= 'V2.0' .and. v20 /= 'v2.0') bFail = .true.
   if (bFail) then
      write(error_unit,*) '>>>> ERROR reading GRP.dat header. This file seems to not being a GRP.dat V2.0'
      stop ERR_GRP_FILE_WRONG_HEADER
   endif
   read(lu,*) nb_points
   read(lu,*)
   do n = 1, nb_points
      read(lu,*) x, y, z, ix, jy
      xmin = min(x,xmin)  ;  xmax = max(x,xmax)
      ymin = min(y,ymin)  ;  ymax = max(y,ymax)
   enddo
   close (lu)

   !computing resolution
   if (nb_points < 4) then
      write(error_unit,'(a)') '>>>> ERROR : not enough points in GRP.dat file'
      stop ERR_NOT_ENOUGH_POINTS_IN_GRP_FILE
   endif
   resolution = estimated_resolution(GRP_dat,width,height,a)

   write(output_unit,'(a,f6.4,a)')  'Estimated resolution : ',resolution,' m/px'

   !writing img_ref.dat
   open(newunit=lu,file=trim(img_ref_dat),form='formatted',status='unknown')
   write(lu,'(a)') 'xmin,ymin'
   write(lu,*) xmin, " ", ymin
   write(lu,'(a)') 'xmax,ymax'
   write(lu,*) xmax, " ", ymax
   write(lu,'(a)') 'resolution'
   write(lu,'(f6.4)') resolution
   write(lu,'(a)') 'size of raw images: height - width'
   write(lu,'(i0,1x,i0)') height, width
   close (lu)

end program gen_img_ref
