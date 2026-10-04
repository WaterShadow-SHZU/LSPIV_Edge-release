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

module lspiv_parameter

integer,parameter :: dp = kind(1.0d0)
!standard subfolders in working directory
character (len=7),  parameter :: img_pgm = 'img_pgm'
character (len=8),  parameter :: img_stab = 'img_stab'
character (len=10), parameter :: img_transf = 'img_transf'
character (len=11), parameter :: outputs_dir = 'outputs.dir'
character (len=9),  parameter :: transects = 'transects'
character (len=10), parameter :: vel_filter = 'vel_filter'
character (len=7),  parameter :: vel_raw = 'vel_raw'
character (len=8),  parameter :: vel_real = 'vel_real'
character (len=8),  parameter :: vel_scal = 'vel_scal'

!standard datafiles
character (len=11), parameter :: img_ref = 'img_ref.dat'
character (len=13), parameter :: PIV_param = 'PIV_param.dat'
character (len=12), parameter :: list_avg = 'list_avg.dat'
character (len=09), parameter :: bathy = 'bathy.dat'
character (len=11), parameter :: bathy_p = 'bathy_p.dat'
character (len=15), parameter :: average_vel = 'average_vel.out'
character (len=05), parameter :: h_dat = 'h.dat'
character (len=13), parameter :: discharge = 'Discharge.dat'
character (len=08), parameter :: grid = 'grid.dat'
character (len=16), parameter :: average_scal = 'average_scal.out'
character (len=07), parameter :: GRP = 'GRP.dat'
character (len=09), parameter :: coeff_dat = 'coeff.dat'
character (len=19), parameter :: manual_tracking = 'manual_tracking.dat'
character (len=14), parameter :: manual_vel = 'manual_vel.out'
character (len=11), parameter :: filters = 'filters.dat'
character (len=13), parameter :: flow_area = 'flow_area.dat' !user defined : flow area, where is the water

!derived types
type point2D
   real(kind=dp) :: x
   real(kind=dp) :: y
end type point2D

contains

function median(array)
   implicit none
   real(kind=dp), dimension(:) :: array
   real(kind=dp)               :: median
   real(kind=dp)               :: max
   integer                     :: i, j, n

   n = size(array)
   do i=1,n
       do j=i+1,n
           if(array(i)>array(j))then
               max=array(i)
               array(i)=array(j)
               array(j)=max
           endif
       end do
   end do

   if (mod(n,2)==0) then
       median=(array(n/2)+array(n/2+1))/2.0
   else
       median=array(n/2 +1)
   endif
end function median

subroutine lire_PIV_param(param_file, Bi, Bj, Sim, Sjm, Sip, Sjp, R_min, R_max, ni, nj, silent)
!  Read the PIV parameters
   use iso_fortran_env, only: error_unit
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: param_file
   integer, intent(out) :: Bi, Bj  ! IA size
   integer, intent(out) :: Sim, Sjm, Sip, Sjp   ! SA size
!            ----------------------
!            |         |          |
!            |         |Sim       |
!            |   Sjm   |    Sjp   |
!            ----------------------
!            |         |          |
!            |         |Sip       |
!            |         |          |
!            ----------------------
   real(kind=dp), intent(out) :: R_min, R_max
   !ni -> image height ; nj -> image width  (matrix view)
   integer, intent(out) :: ni, nj
   ! NOTE: set silent to .true. to skip write(error_unit,...)
   ! NOTE: if silent == .false. or not present, then lire_PIV_param() can write on error_unit
   logical, intent(in), optional :: silent
   ! -- local variables --
   integer :: lw, i
   logical :: verbose

   open(newunit=lw,file=trim(param_file),status='old')
   read(lw,*)
   read(lw,*) Bi
   if (mod(Bi,2) == 0) then
      Bi = Bi + 1
      call corrige_PIV_param(lw, Bi)
      verbose = .true. ; if (present(silent)) verbose = .not.silent
      if (verbose) then
         write(error_unit,'(2(a,i0))') '>>>> WARNING : Bi must be odd ; read value : ', Bi-1,' changed to ',Bi
         write(error_unit,'(3a)')      '              ',trim(param_file),' has been updated'
      endif
   endif
   Bj = Bi
   read(lw,*)
   read(lw,*) Sim ; read(lw,*) Sip ; read(lw,*) Sjm ; read(lw,*) Sjp
   do i = 1, 3
      read(lw,*)
   enddo
   R_min = 0
   R_max = 1
   !nj -> image width ; ni -> image height (matrix view)
   read(lw,*) nj ; read(lw,*) ni
   close (lw)
end subroutine lire_PIV_param


subroutine corrige_PIV_param(lw, Bi)
   use errors, only: ERR_READ_PIV_PARAMETER
   implicit none
   ! -- prototype --
   integer, intent(in) :: lw, Bi
   ! -- variables locales --
   character(len=90) :: ligne(35)
   integer :: ios, n

   rewind (lw)
   read(lw,'(a)') ligne(1)
   read(lw,'(a)') ligne(2)
   write(ligne(2),'(i0)') Bi

   do n = 3, 22
      read(lw,'(a)',iostat=ios) ligne(n)
      if (ios /= 0) stop ERR_READ_PIV_PARAMETER
   enddo
   rewind(lw)
   do n = 1, 22
      write(lw,'(a)') trim(ligne(n))
   enddo
   rewind (lw)
   read(lw,*)
   read(lw,*)
end subroutine corrige_PIV_param

subroutine lire_Grid(grid_file, compt, x, y)
!  Read the grid file
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: grid_file
   integer, intent(out) :: compt
   integer, intent(out), allocatable :: x(:), y(:)
   ! -- local variables --
   integer :: lu, ios, xx, yy

   open(newunit=lu,file=trim(grid_file),status='old')
   !first read to get the size of the grid
   compt = 0
   do
      read(lu,*,iostat=ios) xx, yy
      if (ios /= 0) then
         exit
      else
         compt = compt+1
      endif
   enddo
   rewind(lu)
   !memory allocation
   allocate(x(compt),y(compt))
   !second read to read the grid
   compt = 0
   do
      read(lu,*,iostat=ios) xx, yy
      if (ios /= 0) then
         exit
      else
         compt = compt+1  ;  x(compt) = xx  ;  y(compt) = yy
      endif
   enddo
   close(lu)
end subroutine lire_Grid

subroutine read_img_ref(workdir,xmin, ymin, xmax, ymax, r, width, height)
!Read the image information file img_ref.dat
!X -> abscissa
!Y -> ordinate
!origin = left bottom corner
!r = resolution (m/pixel)
!width & height = image size
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: workdir
   real(kind=dp), intent(out) :: xmin, ymin, xmax, ymax, r
   integer, intent(out) :: width, height
   ! -- local variables --
   integer :: lw

   open(newunit=lw,file=trim(workdir)//'/'//img_ref, status='old')
   read(lw,*) ; read(lw,*) xmin, ymin
   read(lw,*) ; read(lw,*) xmax, ymax
   read(lw,*) ; read(lw,*) r
   read(lw,*) ; read(lw,*) height, width
   close(lw)
end subroutine read_img_ref

subroutine read_coeff_ortho(workdir,n,a)
!read the file coeff.dat for sub_transf_img
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: workdir
   integer, intent(out) :: n
   real(kind=dp), intent(out) :: a(11)
   ! -- local variables --
   integer :: lw, i

   open(newunit=lw,file=trim(workdir)//'/'//coeff_dat,form='formatted',status='old')
   read(lw,*) n
   if (n == 8) then
      do i = 1, 8
         read(lw,*) a(i)
      enddo
   elseif (n == 11) then
      do i = 1, 4
         read(lw,*) a(i)
      enddo
      do i = 1, 3
         read(lw,*) a(i+8)
      enddo
      do i = 1, 4
         read(lw,*) a(i+4)
      enddo
   elseif (n == 0) then
      read(lw,*) a(1)
      read(lw,*) a(2)
   endif
   close (lw)
end subroutine read_coeff_ortho


subroutine run_external_program(command,bwait,istop)
! launch command and manage errors
   use iso_fortran_env, only: output_unit, error_unit
   use errors, only: ERR_BAD_COMMAND
   implicit none
   ! -- prototype --
   character(len=*), intent(in) :: command
   logical, intent(in) :: bwait
   integer, intent(out) :: istop
   ! -- local variables --
   integer :: cstat
   character(len=120) :: err_message

   istop = 0
   if (bwait) then
      call execute_command_line(command,wait=.true.,exitstat=istop,cmdstat=cstat,cmdmsg=err_message)
   else
      call execute_command_line(command,wait=.false.,cmdstat=cstat,cmdmsg=err_message)
   endif
   if (cstat > 0 .and. err_message .ne. 'Termination status of the command-language interpreter cannot be obtained') then
      write(output_unit,'(a,/,a)') 'Something went wrong with the command : ',trim(command)
      write(output_unit,'(a)') trim(err_message)
      write(error_unit,'(a,/,a)') 'Something went wrong with the command : ',trim(command)
      write(error_unit,'(a)') trim(err_message)
      !ignoring case "Termination status of the command-language interpreter cannot be obtained"
      if (cstat /= 1) stop ERR_BAD_COMMAND
   endif
end subroutine run_external_program


function duration(vtime1,vtime2)
!time between vtime1 and vtime2
!vtime1 & vtime2 are assumed to be resulting from date_and_time subroutine
   implicit none
   ! -- prototype --
   integer, intent(in) :: vtime1(8), vtime2(8)
   real(kind=dp) :: duration

   duration = (vtime2(5)*3600.+vtime2(6)*60.+vtime2(7)+vtime2(8)*0.001) &
             -(vtime1(5)*3600.+vtime1(6)*60.+vtime1(7)+vtime1(8)*0.001) &
             +(vtime2(3)-vtime1(3))*86400.
end function duration


logical function is_valid_email(user_email)
! check if the user_email is a valid email
! one word : no blank space
! an @ and a dot after the @
   use iso_fortran_env, only: error_unit
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: user_email
   !logical :: is_valid_email

   if (scan(trim(user_email),' ') > 0) then
      write(error_unit,'(2a)') '>>>> ERROR, invalid email, it contains a blank space : ',user_email
      is_valid_email = .false.
   elseif (scan(trim(user_email),'@') == 0) then
      write(error_unit,'(2a)') '>>>> ERROR, invalid email, it does not contain an @ : ',user_email
      is_valid_email = .false.
   elseif (scan(trim(user_email),'.') == 0) then
      write(error_unit,'(2a)') '>>>> ERROR, invalid email, it does not contain an dot : ',user_email
      is_valid_email = .false.
   elseif (scan(trim(user_email),'.',back=.true.) < scan(user_email,'@')) then
      write(error_unit,'(2a)') '>>>> ERROR, invalid email, no dot after the @ : ',user_email
      is_valid_email = .false.
   else
      is_valid_email = .true.
   endif
end function is_valid_email


subroutine read_last_line(lw,last_line)
!return the lat line of the file connected to unit lw
   implicit none
   ! -- prototype --
   integer, intent(in) :: lw
   character(len=80), intent(out) :: last_line
   ! -- local variables --
   integer :: ios
   character(len=80) :: ligne

   rewind(lw)
   do
      read(lw,'(a)',iostat=ios) ligne
      if (ios /= 0) exit
      last_line = ligne
   enddo
end subroutine read_last_line


subroutine gen_white_PNG(row, col, PNG_file)
! generate a white PNG image with size row rows x col columns
   implicit none
   ! -- prototype --
   character(len=*), intent(in) :: PNG_file
   integer, intent(in) :: row, col
   ! -- local variables
   character(len=:), allocatable :: command
   character(len=9) :: PGM_file = 'white.pgm'
   integer :: lw, color = 8, i, j, istop

   !generate a PGM image
   open(newunit=lw,file=PGM_file,form='formatted',status='unknown')
   write(lw,'(a2)') 'P2'
   write(lw,'(2i5)') col,row
   write(lw,'(a1)') '8'
   do i = 1, row
      write(lw,'(35(i1,1x))') (color,j=1,col)
   enddo
   close(lw)

   allocate(character(len=10+len_trim(PGM_file)+len_trim(PNG_file)) :: command)
   write(command,'(3(a,1x))') 'convert', PGM_file, PNG_file
   istop = 0 ; call run_external_program(command,.true.,istop)

   !removing temp file PGM_file
   open(newunit=lw,file=trim(PGM_file),status='old')
   close(lw,status='delete')
end subroutine gen_white_PNG


pure function f0p(x,p)
! hack tordu pour forcer l'écriture du zéro avant le séparateur décimal pour un format f0.p
   implicit none
   ! -- prototype --
   real(kind=dp), intent(in) :: x
   integer, intent(in) :: p
   character(len=20) :: f0p
   ! -- variable --
   character(len=18) :: tmp
   character(len=6) :: myfmt

   write(myfmt,'(a4,i1,a1)') '(f0.',p,')'
   write(tmp,fmt=myfmt) x
   if (tmp(1:1) == '.') then
      f0p = '0'//tmp(1:)
   elseif (tmp(1:2) == '-.') then
      f0p = '-0'//tmp(2:)
   else
      f0p = tmp(1:)
   endif
end function f0p


logical function is_on_right_side(P0,P1,P)
!determine if point P is on the right of the segment [P0,P1]
!is the case if the determinant of vectors P0P1 and P0P is negative
   implicit none
   ! -- prototype --
   type(point2D), intent(in) :: P0, P1, P
   ! -- local variables --
   real(kind=dp) :: v1x, v2x, v1y, v2y
   v1x = p1%x - p0%x  ;  v1y = p1%y - p0%y
   v2x = p%x - p0%x   ;  v2y = p%y - p0%y

   is_on_right_side = ((v1x * v2y - v1y * v2x) <= 0._dp)
end function is_on_right_side


logical function is_equal_p2d(P,Q)
!return true if p%x == q%x and p%y == q%y
   implicit none
   ! -- prototype --
   type(point2D), intent(in) :: P, Q
   ! -- local variables --
   real(kind=dp), parameter :: eps = 0.001_dp

   is_equal_p2d = (abs(p%x-q%x) + abs(p%y-q%y)) < eps

end function is_equal_p2d


logical function is_inside(xy,p,np)
! compute if point2D XY is inside the polygon P given as an array of point2D
! we assume the polygon is closed, that is p(np) = p(1)
   implicit none
   ! -- prototype --
   integer, intent(in) :: np
   type(point2D), intent(in) :: xy, p(np)
   ! -- local variables --
   real(kind=dp), parameter :: pi = 2._dp*asin(1._dp) !3.14159265359_dp
   integer :: i, j
   real(kind=dp) :: somme, det, nrm1, nrm2, sin_alpha, pscal, cos_alpha

   somme = 0._dp
   do i = 1, np-1
      j = i+1
      det = (p(i)%x-xy%x)*(p(j)%y-xy%y) - (p(i)%y-xy%y)*(p(j)%x-xy%x)
      pscal = (p(i)%x-xy%x)*(p(j)%x-xy%x) + (p(i)%y-xy%y)*(p(j)%y-xy%y)
      nrm1 = sqrt((p(i)%x-xy%x)**2 + (p(i)%y-xy%y)**2)
      nrm2 = sqrt((p(j)%x-xy%x)**2 + (p(j)%y-xy%y)**2)
      if (abs(nrm1*nrm2) < 1.0e-20_dp) then !xy = p(i) or xy = p(i+1)
         is_inside = .true.
         return
      else
         sin_alpha = det/(nrm1*nrm2)
         cos_alpha = pscal/(nrm1*nrm2)
         if (abs(cos_alpha) <= 1) then
            somme = somme + sign(1._dp,sin_alpha)*acos(cos_alpha)
         endif
      endif
   enddo
   somme = abs(somme) !important car on a pu tourner dans un sens ou l'autre
   is_inside = abs(somme-2._dp*Pi) <= Pi
end function is_inside

end module lspiv_parameter
