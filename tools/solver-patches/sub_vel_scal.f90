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
module mod_vel_scal

   contains

subroutine sub_vel_scal(workdir)
!     calcule les scalaires associes au champ de vitesse
!     M Jodeau le 13-07-2012
!     modif par JLC: format '(A)' au lieu de * pour les strings
!     modif par JLC: ajout du calcul du fichier average_scal.out
!     modif par JBF: passage en format libre et double précision
!     modif par MJ 11-02-2015 : 1. traite les fichiers de vitesse filtres (et non plus
!                               les vitesses brutes)
!                               2. calcule la norme des vitesses moy.
!     modif par JBF 13-02-2015 : simplification et allocation dynamique de mémoire
!     modif par MJ 20-02-2015 : - séparation des étapes 1. et 2. (dans moy_scal.f90)
!                               - boucle sur i modifiée
!     modif par BM 23-02-2015 : - Changement du format de sortie pour etre sur que chaque
!                                 valeur soit séparée par au moins un blanc.
!     modif par JBF 27-02-2015 : utilisation de iostat_end, iostat_err pour tester proprement
!                                l'arrêt de lecture des fichiers

   use iso_fortran_env, only: error_unit
   use errors, only: ERR_READ_LIST_AVG, ERR_READ_FILTER, ERR_NB_DATA_POINT_WRONG_VALUE
   use lspiv_parameter, only: dp, list_avg, outputs_dir, vel_filter, vel_scal
   implicit none
   ! protype
   character (len=*), intent(in) :: workdir !working directory

   integer :: i,k,io_status,nb_files,nb_data_points
   real(kind=dp) :: x,y,u,v,r,n,omega,div
   real(kind=dp),allocatable :: uu(:,:),vv(:,:),xx(:,:),yy(:,:)
   integer,allocatable :: nb(:)
   character(len=160) :: BaseName
   character(len=:), allocatable :: NomIn, NomOut
   integer :: lu, lv, lw, bsize

! comptage des données
   !lecture du fichier list_avg.dat pour compter le nombre de fichiers de vitesse
   open(newunit=lu,file=trim(workdir)//'/'//outputs_dir//'/'//list_avg,status='old')
   nb_files = 0  ;  bsize = 0
   do
      read(lu,*,iostat=io_status) BaseName
      if (is_iostat_end(io_status)) exit
      if (io_status /= 0) then
          write(error_unit,'(a)') 'sub_vel_scal() : Erreur de lecture de list_avg.dat'
          stop ERR_READ_LIST_AVG
      endif
      nb_files = nb_files+1
      bsize = max(bsize,len_trim(BaseName)) !taille maximale des noms de fichier dans list_avg.dat
   enddo
   close(lu)
   !lecture du dernier fichier pour compter le nombre de points de données
   allocate(character(len=len_trim(workdir)+bsize+20) :: NomIn)
   NomIn = trim(workdir)//'/'//vel_filter//'/'//'filter_'//trim(BaseName)
   open(newunit=lu,file=trim(NomIn),status='old')
   nb_data_points = 0
   do
      read(lu,*,iostat=io_status) x, y, u, v
      if (is_iostat_end(io_status)) exit
      if (io_status /= 0) then
          write(error_unit,'(a)') 'sub_vel_scal() : Erreur de lecture de '//trim(NomIn)
          stop ERR_READ_FILTER
      endif
      nb_data_points = nb_data_points+1
   enddo
   close(lu)


   allocate(uu(nb_data_points,nb_files),vv(nb_data_points,nb_files))
   allocate(xx(nb_data_points,nb_files),yy(nb_data_points,nb_files))
   allocate(nb(nb_data_points))


! ecriture des fichiers vel_scal_piv00x
   open(newunit=lu,file=trim(workdir)//'/'//outputs_dir//'/'//list_avg,status='old')
   allocate(character(len=len_trim(workdir)+bsize+20) :: NomOut)
   k = 0
   do
      read(lu,*,iostat=io_status) BaseName
      if (is_iostat_end(io_status)) exit
      if (is_iostat_eor(io_status) .OR. io_status > 0) then
          write(error_unit,'(a)') 'sub_vel_scal() : Erreur de lecture de list_avg.dat'
          stop ERR_READ_LIST_AVG
      endif
      NomIn = trim(workdir)//'/'//vel_filter//'/'//'filter_'//trim(BaseName)
      k = k+1

      open(newunit=lv,file=trim(NomIn),status='old') ! ouverture du fichier de vitesse

      ! ecriture du fichier de scalaires
      NomOut = trim(workdir)//'/'//vel_scal//'/'//'scal_'//trim(BaseName)
      open(newunit=lw,file=trim(NomOut),status='unknown')
      do i = 1, nb_data_points
          read(lv,*,iostat=io_status) xx(i,k),yy(i,k),uu(i,k),vv(i,k),r
          if (is_iostat_end(io_status)) then
              write(error_unit,'(a)') 'sub_vel_scal() : Valeur de nb_data_points fausse'
              stop ERR_NB_DATA_POINT_WRONG_VALUE
          endif
          if (io_status /= 0) then
              write(error_unit,'(a)') 'sub_vel_scal() : Erreur de lecture de '//trim(NomIn)
              stop ERR_READ_FILTER
          endif
          n = sqrt(uu(i,k)*uu(i,k)+vv(i,k)*vv(i,k))

          omega = 4._dp             ! calcul du rotationnel (a faire)
          div = 5._dp               ! calcul de la divergence (a faire)

          write(lw,*) xx(i,k),yy(i,k),n,r,omega,div

      enddo
      close(lv)
      close(lw)
   enddo
   close(lu)

end subroutine sub_vel_scal

end module mod_vel_scal
