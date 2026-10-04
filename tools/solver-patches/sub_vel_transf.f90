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

module mod_vel_transf

   use lspiv_parameter, only: dp, vel_raw, piv_param, img_ref, list_avg, outputs_dir, vel_real

   contains

subroutine sub_vel_transf(workdir, dt_in)
!     créé à partir de filter.f, transforme les vecteurs vitesses de l'espace image transformée à l'espace réel
!     M Jodeau le 14-11-2011
!     modif par JBF 27-02-2015 : utilisation de iostat_end pour tester proprement
!                                l'arrêt de lecture des fichiers
   implicit none
   ! protype
   character (len=*), intent(in) :: workdir !working directory
   real(kind=dp), intent(in), optional :: dt_in

   integer :: i, io_status
   real(kind=dp) :: x,y,u,v,xmin,ymin,xmax,ymax,resol,Dt,r
   character(len=160) :: BaseName, line
   character(len=:), allocatable :: NomIn, NomOut
   integer :: lu, lv, lw, bsize, usp


   open(newunit=lu,file=trim(workdir)//'/'//outputs_dir//'/'//PIV_param,status='old')
   do i = 1,8
      read(lu,*)
   enddo
   read(lu,'(a)',iostat=io_status) line
   if (present(dt_in)) then
     Dt = dt_in
   else
     read(line, *,iostat=io_status)Dt, usp
     if (io_status .ne. 0 .or. usp <= 0) usp = 1
     Dt = Dt * usp
   endif
   close(lu)

   open(newunit=lu,file=trim(workdir)//'/'//outputs_dir//'/'//img_ref,status='old')
   read(lu,*)  ;  read(lu,*) xmin,ymin
   read(lu,*)  ;  read(lu,*) xmax,ymax
   read(lu,*)  ;  read(lu,*) resol
   close(lu)

   open(newunit=lu,file=trim(workdir)//'/'//outputs_dir//'/'//list_avg,status='old')
   bsize = 0
   do
      read(lu,*,iostat=io_status) BaseName
      if (is_iostat_end(io_status)) exit
      bsize = max(bsize,len_trim(BaseName))
   enddo
   rewind(lu)
   allocate(character(len=len_trim(workdir)+bsize+15) :: NomIn, NomOut)
   do
      read(lu,*,iostat=io_status) BaseName
      if (is_iostat_end(io_status)) exit

      NomIn = trim(workdir)//'/'//vel_raw//'/'//trim(BaseName)
      open(newunit=lv,file=trim(NomIn),status='old')
      NomOut = trim(workdir)//'/'//vel_real//'/'//'real_'//trim(BaseName)
      open(newunit=lw,file=trim(NomOut),status='unknown')

      do
         read(lv,*,iostat=io_status) x,y,u,v,r
         if (is_iostat_end(io_status)) exit

         y = y*resol+xmin
         x = x*resol+ymin
         u = (u*resol)/Dt
         v = (v*resol)/Dt

         write(lw,*) y,x,v,u,r
      enddo
      close(lv)
      close(lw)
   enddo
   close(lu)
end subroutine sub_vel_transf

end module mod_vel_transf
