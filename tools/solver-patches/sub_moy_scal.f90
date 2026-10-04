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

module mod_moy_scal

   use lspiv_parameter, only: dp, median, average_scal, filters, list_avg, outputs_dir, vel_filter

   contains

subroutine sub_moy_scal(workdir)
!     calcule les moyennes des scalaires associes au champ de vitesse
!     M Jodeau le 20-02-2015
!     cree a partir de vel_scal.f90 du 13-02-2015
!     modif par BM 23-02-2015 : - Changement du format de sortie pour etre sur que chaque
!                                 valeur soit séparée par au moins un blanc.
!     modif par JBF 27-02-2015 : utilisation de is_iostat_end() pour tester proprement
!                                l'arrêt de lecture des fichiers
!     modif par tterraz 05/10/2022 : utilisation de la moyenne itérative pour plus de stabilité
!                                    quand les vecteurs sont grands
   use iso_fortran_env, only: error_unit
   use errors, only: ERR_READ_LIST_AVG, ERR_READ_FILTER, ERR_NB_DATA_POINT_WRONG_VALUE
   implicit none
   ! protype
   character (len=*), intent(in) :: workdir !working directory

   integer :: i,j,k,io_status,nb_files,nb_data_points,aggregType
   real(kind=dp) :: x,y,u,v,r,n,omega,div
   real(kind=dp), allocatable :: nmoy(:),rmoy(:),omegamoy(:),divmoy(:),xmoy(:),ymoy(:)
!    real(kind=dp), allocatable :: sum_u(:),sum_v(:)
   real(kind=dp), allocatable :: mean_u(:),mean_v(:),tab_u(:),tab_v(:)
   real(kind=dp), allocatable :: uu(:,:),vv(:,:),xx(:,:),yy(:,:)
!    integer, allocatable :: nb(:)
   character(len=180) :: BaseName
   character(len=:), allocatable :: NomIn
   integer :: lw, lu, lu13

! comptage des donnees
   !lecture du fichier list_avg.dat pour compter le nombre de fichiers de vitesse
   open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//list_avg,status='old')
   open(newunit=lu13,file=trim(workdir)//'/'//outputs_dir//'/'//filters,status='unknown')

   ! Read mean/median param
   do i = 1,20
    read(lu13,*)
   end do
   read(lu13,*) aggregType
   close(lu13)

   nb_files = 0
   do
      read(lw,'(a)',iostat=io_status) BaseName
      if (is_iostat_end(io_status)) exit
      if (io_status /= 0) then
          write(error_unit,'(a)') 'sub_moy_scal() : Erreur de lecture de list_avg.dat'
          stop ERR_READ_LIST_AVG
      endif
      nb_files = nb_files+1
   enddo
   close(lw)
   !lecture du dernier fichier pour compter le nombre de points de donnees
   allocate (character(len=len_trim(workdir)+len_trim(BaseName)+20) :: NomIn)
   NomIn = trim(workdir)//'/'//vel_filter//'/filter_'//trim(BaseName)
   open(newunit=lw,file=trim(NomIn),status='old')
   nb_data_points = 0
   do
      read(lw,*,iostat=io_status) x, y, u, v
      if (is_iostat_end(io_status)) exit
      if (io_status /= 0) then
          write(error_unit,'(3a)') 'sub_moy_scal() : Erreur de lecture de '//trim(NomIn)
          stop ERR_READ_FILTER
      endif
      nb_data_points = nb_data_points+1
   enddo
   close(lw)

   allocate(nmoy(nb_data_points), rmoy(nb_data_points), omegamoy(nb_data_points))
   allocate(divmoy(nb_data_points),xmoy(nb_data_points),ymoy(nb_data_points))
!    allocate(sum_u(nb_data_points),sum_v(nb_data_points))
   allocate(mean_u(nb_data_points),mean_v(nb_data_points))
   allocate(uu(nb_data_points,nb_files),vv(nb_data_points,nb_files))
   allocate(xx(nb_data_points,nb_files),yy(nb_data_points,nb_files))
!    allocate(nb(nb_data_points))

   rmoy = 0._dp
   omegamoy = 0._dp
   divmoy = 0._dp

! ecriture des fichiers vel_scal_piv00x
   open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//list_avg,status='old')
   k = 0
   do
      read(lw,*,iostat=io_status) BaseName
      if (is_iostat_end(io_status)) exit
      if (io_status /= 0) then
          write(error_unit,'(a)') 'sub_moy_scal() : Erreur de lecture de list_avg.dat'
          stop ERR_READ_LIST_AVG
      endif
      NomIn = trim(workdir)//'/'//vel_filter//'/filter_'//trim(BaseName)
      k = k+1

      open(newunit=lu,file=trim(NomIn),status='old') ! ouverture du fichier de vitesse

      do i = 1,nb_data_points
         read(lu,*,iostat=io_status) xx(i,k),yy(i,k),uu(i,k),vv(i,k),r
!          if (is_iostat_end(io_status)) stop 'sub_moy_scal() : Valeur de nb_data_points fausse'
         if (io_status /= 0) then
             write(error_unit,'(a)') 'sub_moy_scal() : Valeur de nb_data_points fausse'
             stop ERR_NB_DATA_POINT_WRONG_VALUE
         endif
!          if (io_status /= 0) stop 'sub_moy_scal() : Erreur de lecture de '//trim(NomIn)

         n = sqrt(uu(i,k)*uu(i,k)+vv(i,k)*vv(i,k))

         omega = 4._dp             ! calcul du rotationnel (a faire)
         div = 5._dp               ! calcul de la divergence (a faire)

         rmoy(i) = rmoy(i)+r
         omegamoy(i) = omegamoy(i)+omega
         divmoy(i) = divmoy(i)+div
         xmoy(i) = xx(i,k)
         ymoy(i) = yy(i,k)
      enddo
      close(lu)

   enddo

   close(lw)

! calcul des moyennes en coherence avec moy_ec.f90

   do i = 1, nb_data_points ! Number of data points in each velocity field
!       sum_u(i) = 0._dp
!       sum_v(i) = 0._dp
      mean_u(i) = 0
      mean_v(i) = 0
      k=0
!       nb(i) = 0
      do j = 1, nb_files ! number of files
         if ((uu(i,j).ne.0._dp).or.(vv(i,j).ne.0._dp)) then
!             nb(i) = nb(i)+1
           k = k+1
           if (aggregType.eq.1) then
             mean_u(i) = mean_u(i)+( (uu(i,j) - mean_u(i))/float(k) )
             mean_v(i) = mean_v(i)+( (vv(i,j) - mean_v(i))/float(k) )
           endif
         endif
!          sum_u(i) = sum_u(i)+uu(i,j)
!          sum_v(i) = sum_v(i)+vv(i,j)
      enddo
      if ((aggregType.eq.0).and.(k>4)) then ! Median
         allocate(tab_u(k),tab_v(k))
         k = 1
         do j = 1,nb_files
            if ((uu(i,j).ne.0._dp).or.(vv(i,j).ne.0._dp)) then
               tab_u(k) = uu(i,j)
               tab_v(k) = vv(i,j)
               k = k+1
            endif
         enddo
         mean_u(i) = median(tab_u)
         mean_v(i) = median(tab_v)
         deallocate(tab_u,tab_v)
       end if
!       if (nb(i).ne.0) then
!          mean_u(i) = sum_u(i)/nb(i)
!          mean_v(i) = sum_v(i)/nb(i)
!       else
!          mean_u(i) = 0._dp
!          mean_v(i) = 0._dp
!       endif
      nmoy(i) = sqrt(mean_u(i)*mean_u(i)+mean_v(i)*mean_v(i))
    enddo
! ----------------------------------------------------------------

! ecriture du fichier des parametres moyens
   open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//average_scal,status='unknown')
   do i = 1, nb_data_points
      rmoy(i) = rmoy(i)/nb_files
      omegamoy(i) = omegamoy(i)/nb_files
      divmoy(i) = divmoy(i)/nb_files
      write(lw,*) xmoy(i),ymoy(i),nmoy(i),rmoy(i),omegamoy(i),divmoy(i)
   enddo
   close(lw)
   deallocate (rmoy, omegamoy, divmoy, mean_u, mean_v)
end subroutine sub_moy_scal

end module mod_moy_scal
