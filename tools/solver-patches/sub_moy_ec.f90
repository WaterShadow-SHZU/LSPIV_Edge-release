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

module mod_moy_ec

   use lspiv_parameter, only: dp

   contains

subroutine sub_moy_ec(dir1, dir2, dir3)

!     modif par BM 23-02-2015 : - Changement du format de sortie pour etre sur que chaque
!                                 valeur soit séparée par au moins un blanc.
!     modif par JBF 27-02-2015 : utilisation de iostat_end pour tester proprement
!                                l'arrêt de lecture des fichiers
!     modif par tterraz 05/10/2022 : utilisation de la moyenne itérative pour plus de stabilité
!                                    quand les vecteurs sont grands
   use iso_fortran_env, only: error_unit
   use errors, only: ERR_SUB_MOY_EC
   use lspiv_parameter, only: median, average_vel, filters, list_avg
   implicit none
   ! -- prototype --
   character(len=*), intent(in) :: dir1, dir2, dir3
   ! -- local variables --
   integer :: i,j,k,compteur,compt,nn, ios, compt0,aggregType
!    integer,allocatable :: nb(:)
   character(len=20), allocatable :: BaseName(:)
   character(len=20) :: tmp
   !character(len=60) :: NomFich
   character (len=:), allocatable :: NomFich
!    real(kind=dp),allocatable :: sum_u(:), sum_v(:)
   real(kind=dp),allocatable :: mean_u(:), mean_v(:), tab_u(:),tab_v(:)
   real(kind=dp) :: moy
   real(kind=dp),allocatable :: u(:,:), v(:,:), x(:,:), y(:,:)
   integer :: lu10, lu12,lu13
   logical :: filter_needed

   open(newunit=lu10,file=trim(dir1)//'/'//list_avg,status='old')
   open(newunit=lu12,file=trim(dir2)//'/'//average_vel,status='unknown')
   inquire(file=trim(dir1)//'/'//filters, exist=filter_needed)
   if (filter_needed) then
      open(newunit=lu13,file=trim(dir1)//'/'//filters,status='unknown')
      ! Read mean/median param
      do i = 1,20
        read(lu13,*)
      end do
      read(lu13,*) aggregType
      close(lu13)
   else
      aggregType = 1
   endif
   !read the file to count the number of records
   i = 0
   do
      i = i+1
      read(lu10,*,iostat=ios) tmp
      if (is_iostat_end(ios)) exit
   enddo
   compteur = i-1 ! Number of velocity fields to average
   rewind(lu10)
   !read the file
   allocate(BaseName(compteur))
   do i = 1, compteur
      read(lu10,*,iostat=ios) BaseName(i)
      if (is_iostat_end(ios)) exit
   enddo
   close (lu10)

   allocate(character(len=len_trim(dir3)+27) :: NomFich)
   NomFich = trim(dir3)//'filter_'//BaseName(1)
   call count_vectors(NomFich,compt)
   compt0 = compt
   !allocation des autres tableaux
!    allocate(sum_u(compt),sum_v(compt),nb(compt))
   allocate(mean_u(compt),mean_v(compt))
   allocate(u(compt,compteur),v(compt,compteur),x(compt,compteur),y(compt,compteur))

   do i = 1, compteur
      NomFich = trim(dir3)//'filter_'//BaseName(i)
      call readfile(NomFich,i,compt,x,y,u,v)
      if (compt /= compt0) then
         write(error_unit,'(3a)') '>>>> ERROR in moy_ec.f90 : the number of records in the file ', &
                       trim(nomfich),' is not equal to the number of records in previous files'
         stop ERR_SUB_MOY_EC
      endif
   enddo

   nn = 0
   moy = 0
   do i = 1, compt ! Number of data points in each velocity field
!       sum_u(i) = 0
!       sum_v(i) = 0
        mean_u(i) = 0
        mean_v(i) = 0
        k=0
!       nb(i) = 0
      do j = 1, compteur ! Number of time step
         if ((abs(u(i,j)) > 1.0e-20_dp) .or. (abs(v(i,j)) > 1.0e-20_dp)) then
!             nb(i) = nb(i)+1
             k = k+1 ! Count non filtered data
             if (aggregType.eq.1)then
               mean_u(i) = mean_u(i)+((u(i,j) - mean_u(i))/float(k))
               mean_v(i) = mean_v(i)+((v(i,j) - mean_v(i))/float(k))
             endif
         endif
!          sum_u(i) = sum_u(i)+u(i,j)
!          sum_v(i) = sum_v(i)+v(i,j)
      enddo
      if ((aggregType.eq.0).and.(k>4)) then ! Median
         allocate(tab_u(k),tab_v(k))
         k = 1
         do j = 1,compteur
            if ((abs(u(i,j)) > 1.0e-20_dp) .or. (abs(v(i,j)) > 1.0e-20_dp)) then
               tab_u(k) = u(i,j)
               tab_v(k) = v(i,j)
               k = k+1
            endif
         enddo
         mean_u(i) = median(tab_u)
         mean_v(i) = median(tab_v)
         deallocate(tab_u,tab_v)
       end if
!       if (nb(i) .ne. 0) then
!          mean_u(i) = sum_u(i)/nb(i)
!          mean_v(i) = sum_v(i)/nb(i)
!       else
!          mean_u(i) = 0
!          mean_v(i) = 0
!       endif

      write(lu12,*) x(i,1), y(i,1), mean_u(i), mean_v(i)
   enddo
   close(lu12)
!    deallocate (sum_u, sum_v)
   deallocate (mean_u, mean_v, u, v, x, y)
end subroutine sub_moy_ec


subroutine count_vectors(NomFich,compt)
   implicit none
   ! -- prototype --
   integer, intent(out) :: compt
   character(len=*),intent(in) :: NomFich
   ! -- local variables --
   real(kind=dp) :: x,y,u,v
   integer :: i, ios, lu11

   open(newunit=lu11,file=trim(NomFich),status='old')
   i = 0
   do
      i = i+1
      read(lu11,*,iostat=ios) x, y, u, v
      if (is_iostat_end(ios)) exit
   enddo
   compt = i-1
   close(lu11)
end subroutine count_vectors


subroutine readfile(NomFich,k,compt,x,y,u,v)
   implicit none
   ! -- prototype --
   integer, intent(in) :: k
   integer, intent(out) :: compt
   character(len=*),intent(in) :: NomFich
   real(kind=dp),intent(inout) :: x(:,:),y(:,:),u(:,:),v(:,:)
   ! -- local variables --
   integer :: i, ios, lu11
   real(kind=dp) :: xx, yy, uu, vv

   open(newunit=lu11,file=trim(NomFich),status='old')
   i = 0
   do
      i = i+1
      read(lu11,*,iostat=ios) xx, yy, uu, vv
      if (is_iostat_end(ios)) then
         exit
      else
         x(i,k) = xx ; y(i,k) = yy ; u(i,k) = uu ; v(i,k) = vv
      endif
   enddo
   compt = i-1
   close(lu11)
end subroutine readfile

end module mod_moy_ec
