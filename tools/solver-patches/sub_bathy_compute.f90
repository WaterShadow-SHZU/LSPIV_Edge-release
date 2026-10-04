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

module mod_bathy_compute

   use lspiv_parameter, only: dp, bathy, bathy_p, piv_param

   contains

subroutine sub_bathy_compute(workdir)
! ---------------------------
! LSPIV-solvers, V1.0, 2014
!
! Jerome Le Coz & Jean-Baptiste Faure, Irstea
!
! Contributions:
! -------------
! LSPIV-solvers was built on original developments from the PhD work of
! Alex Hauet (LTHE Grenoble, University of Iowa), following the seminal works
! on LSPIV by Ichiro Fujita and Marian Muste.
! Recent contributions by Alex Hauet (EDF) and Magali Jodeau (EDF) are also acknowledged.
!
!     modif par BM 23-02-2015 : - bathy_p.dat est ecrit dans outputs.dir
!     modif par JLC 18-11-2016 : skip 3 lines more in PIV_param.dat (new format)
!     modif by JLC 02-03-2018 : read and write surface velocity coefficients, correction of transect interpolation
!     modif by JLC 19-06-2019 : extend float formats to allow for geographical coordinates (f10.3 replaced by f12.3)
!     modif by JLC 03-12-2019 : interpolate missing coefficient values

   implicit none
   ! -- prototype --
   character(len=*), intent(in)  :: workdir !base directory
   ! -- local variables --
   integer :: i, j, k, m, compt, nxp, ios, msize, kk, np_purge
   real(kind=dp), allocatable :: x(:), y(:), z(:), xm(:), ym(:), zm(:), xp(:), xpm(:)
   real(kind=dp), allocatable :: coeffk(:), coeffm(:)
   real(kind=dp) :: coeff, temp, a, b, n, Dxp, intxp, xpa, xa, ya, za, coeffa, ratio, a1, a2
   integer :: lu14, lu10, io_status
   integer, parameter :: long = 26
   character(len=160) :: line

   open(newunit=lu14,file=trim(workdir)//'/'//PIV_param,status='old')
   do i = 1, 13
      read(lu14,*)
   enddo
   read(lu14,*) coeff
   do i= 1, 3
      read(lu14,*)
   enddo
   read(lu14,'(a)',iostat=io_status) line
   read(line, *,iostat=io_status)Dxp, np_purge
   if (io_status .ne. 0 .or. np_purge <= 0) np_purge = 0
   close(lu14)

   open(newunit=lu10,file=trim(workdir)//'/'//bathy,status='old')
   !counts the number of records
   k = 1
   do
      read(lu10,*,iostat=ios) xa, ya, za
      if (ios /= 0) then
         exit
      else
         k = k+1
      endif
   enddo
   compt = k-1    !nombre de points de bathy
   rewind(lu10)
   !memory allocation
   allocate(x(compt),y(compt),z(compt),xp(compt),coeffk(compt))
   if (abs(coeff+1) < 1.0e-20_dp) then ! if alpha has to be read in transect input file
      do k = 1, compt
         read(lu10,*) x(k), y(k), z(k), coeffk(k)
      enddo
   else ! default case: single alpha value from PIV_param.dat
      do k = 1, compt
         read(lu10,*) x(k), y(k), z(k)
         coeffk(k) = coeff
      enddo
   endif
   close(lu10)

   open(newunit=lu10,file=trim(workdir)//'/'//bathy_p,status='unknown')
   write(lu10,*) ' projected bathymetry profile'
   write(lu10,*) ' x0  y0 (start point coordinates)'
   write(lu10,'(2f12.3)') x(1), y(1)
   write(lu10,*) 'a   b (unit vector coordinates)'

   n = sqrt((x(compt)-x(1))**2+(y(compt)-y(1))**2)
   a = (x(compt)-x(1)) / n
   b = (y(compt)-y(1)) / n
   write(lu10,'(2f12.3)') a, b
   write(lu10,*) 'xp  x   y   zb   alpha (position, bed elevation, coefficient)'

! bathymetry projection
   do k = 1,compt
      temp = x(k)
      x(k) = a*a*x(k) + a*b*y(k) + b*b*x(1) - a*b*y(1)
      y(k) = a*b*temp + b*b*y(k) - a*b*x(1) + a*a*y(1)
      xp(k) = sqrt( (x(k)-x(1))**2 + (y(k)-y(1))**2 )
   enddo

! interpolation of missing coefficients
   do k=1,compt
      if (abs(coeffk(k)+1) < 1.0e-20_dp) then
            kk = k+1
            do while((kk.le.compt).and.(abs(coeffk(kk)+1) < 1.0e-20_dp))
               kk = kk+1
            enddo
            j = k-1
            do while((j.ge.1).and.(abs(coeffk(j)+1) < 1.0e-20_dp))
               j = j-1
            enddo
            if (kk.le.compt) then
               if (j.ge.1) then
                  a1 = 1./abs(xp(kk)-xp(k))
                  a2 = 1./abs(xp(j)-xp(k))
                  coeffk(k) = (a1*coeffk(kk)+a2*coeffk(j))/(a1+a2)
               else
                  coeffk(k) = coeffk(kk)
               endif
            else
               if (j.ge.1) then
                  coeffk(k) = coeffk(j)
               else
                  coeffk(k) = 0.85
               endif
            endif
         endif
      enddo

! sort bathy points
   do k = 2, compt
      xpa = xp(k)
      xa = x(k)
      ya = y(k)
      za = z(k)
      coeffa = coeffk(k)
      do j = k-1, 1, -1
         if (xp(j) .le. xpa) goto 10
         xp(j+1) = xp(j)
         x(j+1)  = x(j)
         y(j+1)  = y(j)
         z(j+1)  = z(j)
         coeffk(j+1) = coeffk(j)
      enddo
      j = 0
10    xp(j+1) = xpa
      x(j+1)  = xa
      y(j+1)  = ya
      z(j+1)  = za
      coeffk(j+1) = coeffa
   enddo

   if (np_purge > 2) then
      call purge(x, y, z, xp, coeffk, np_purge, compt)
   endif

! Count the size msize of xpm,xm,ym,zm
   if (Dxp > 0.0) then
      msize = compt
      do k = 2, compt
          if ( (xp(k)-xp(k-1)) .gt. Dxp ) then
              nxp = floor((xp(k)-xp(k-1))/Dxp)
              msize = msize+nxp
          endif
      enddo

      !memory allocation
      allocate(xm(msize),ym(msize),zm(msize),xpm(msize),coeffm(msize))

      m = 1
      xpm(m) = 0
      xm(m)  = x(m)
      ym(m)  = y(m)
      zm(m)  = z(m)
      coeffm(m) = coeffk(m)

      do k = 2, compt
      ! bathymetry interpolation
          if ( (xp(k)-xp(k-1)) .gt. Dxp ) then
              nxp = floor((xp(k)-xp(k-1))/Dxp)
              intxp = (xp(k)-xp(k-1))/(nxp+1)
              do j = 1, nxp
                  m = m+1
                  xpm(m) = xp(k-1)+j*intxp
                  xm(m)  = x(k-1)+a*j*intxp
                  ym(m)  = y(k-1)+b*j*intxp
                  ratio  = (xpm(m)-xp(k-1))/(xp(k)-xp(k-1))
                  zm(m)  = z(k-1)+(z(k)-z(k-1))*ratio
                  coeffm(m) = coeffk(k-1)+(coeffk(k)-coeffk(k-1))*ratio
              enddo
          endif
          m = m+1
          xpm(m) = xp(k)
          xm(m)  = x(k)
          ym(m)  = y(k)
          zm(m)  = z(k)
          coeffm(m) = coeffk(k)
      enddo
      deallocate (xp, x, y, z, coeffk)
   else
      call move_alloc(xp, xpm)
      call move_alloc(x, xm)
      call move_alloc(y, ym)
      call move_alloc(z, zm)
      call move_alloc(coeffk, coeffm)
   endif

! write file bathy_p
   do k = 1, m
      write(lu10,'(5f12.3)') xpm(k),xm(k),ym(k),zm(k),coeffm(k)
   enddo
   close(lu10)

! deallocate all arrays
   deallocate (xm, ym, zm, xpm, coeffm)
end subroutine sub_bathy_compute

subroutine purge(x, y, z, xp, coeffk, np_purge, compt)

    use iso_fortran_env, only: error_unit
    use errors, only: ERR_PURGE
    implicit none

    real(kind=dp), allocatable, intent(inout) :: x(:), y(:), z(:), xp(:), coeffk(:) ! modified in place
    integer, intent(in) :: np_purge ! number of points to keep
    integer, intent(inout) :: compt ! size of the in/out arrays
    !--- local ---!
    real(kind=dp), allocatable :: x_tmp(:), y_tmp(:), z_tmp(:), xp_tmp(:), coeffk_tmp(:), area_tmp(:), area(:)
    integer :: to_rm_tmp(1)
    integer :: to_rm ! liste des indices à enlever
    integer :: i, j
    real(kind=dp) :: min_area, a2, b2, c2

    if (compt <= np_purge) return
    allocate(area(compt))
    area(1) = 0.0
    area(compt) = 0.0
    do i = 2, compt-1
        area(i) = get_area(x(i-1:i+1),&
                            y(i-1:i+1),&
                            z(i-1:i+1))
    enddo

    do while (compt > np_purge) ! rm points one by one
!         to_rm_tmp = maxloc(area)
        to_rm = 2
        min_area = abs(area(2))
        do i = 3, compt-1
            if (abs(area(i)) < min_area) then
                min_area = abs(area(i))
                to_rm = i
            endif
        enddo
        if (to_rm > compt-1 .or. to_rm <= 1) then
            write(error_unit,'(a)') 'Erreur dans purge'
            stop ERR_PURGE
        endif
        allocate(area_tmp(compt-1))
        allocate(x_tmp(compt-1))
        allocate(y_tmp(compt-1))
        allocate(z_tmp(compt-1))
        allocate(xp_tmp(compt-1))
        allocate(coeffk_tmp(compt-1))
        x_tmp(1:to_rm-1) = x(1:to_rm-1)
        x_tmp(to_rm:compt-1) = x(to_rm+1:compt)
        y_tmp(1:to_rm-1) = y(1:to_rm-1)
        y_tmp(to_rm:compt-1) = y(to_rm+1:compt)
        z_tmp(1:to_rm-1) = z(1:to_rm-1)
        z_tmp(to_rm:compt-1) = z(to_rm+1:compt)
        xp_tmp(1:to_rm-1) = xp(1:to_rm-1)
        xp_tmp(to_rm:compt-1) = xp(to_rm+1:compt)
        coeffk_tmp(1:to_rm-1) = coeffk(1:to_rm-1)
        coeffk_tmp(to_rm:compt-1) = coeffk(to_rm+1:compt)
        area_tmp(1:to_rm-2) = area(1:to_rm-2)
        area_tmp(to_rm+1:compt-1) = area(to_rm+2:compt)
        do i = to_rm-1, to_rm
            if (i == 1) cycle
            if (i == compt - 1) cycle
            area_tmp(i) = get_area(x_tmp(i-1:i+1),&
                                   y_tmp(i-1:i+1),&
                                   z_tmp(i-1:i+1))
        enddo
        call move_alloc(x_tmp, x)
        call move_alloc(y_tmp, y)
        call move_alloc(z_tmp, z)
        call move_alloc(xp_tmp, xp)
        call move_alloc(coeffk_tmp, coeffk)
        call move_alloc(area_tmp, area)
        compt = compt - 1
    enddo
end subroutine purge

function get_angle(x, y, z)
    implicit none

    real(kind=dp) :: x(3), y(3), z(3), xp(3)
    real(kind=dp) :: get_angle
    real(kind=dp) :: a2, b2, c2
    a2 = (x(1)-x(2))*(x(1)-x(2)) + &
         (y(1)-y(2))*(y(1)-y(2)) + &
         (z(1)-z(2))*(z(1)-z(2))
    b2 = (x(3)-x(2))*(x(3)-x(2)) + &
         (y(3)-y(2))*(y(3)-y(2)) + &
         (z(3)-z(2))*(z(3)-z(2))
    c2 = (x(3)-x(1))*(x(3)-x(1)) + &
         (y(3)-y(1))*(y(3)-y(1)) + &
         (z(3)-z(1))*(z(3)-z(1))
    get_angle = acos((a2+b2-c2)/(2*sqrt(a2*b2)))
end function get_angle

function get_height(x, y, z)
    implicit none

    real(kind=dp) :: x(3), y(3), z(3), xp(3)
    real(kind=dp) :: get_height
    real(kind=dp) :: a2, b2, c2
    a2 = (x(1)-x(2))*(x(1)-x(2)) + &
         (y(1)-y(2))*(y(1)-y(2)) + &
         (z(1)-z(2))*(z(1)-z(2))
    b2 = (x(3)-x(2))*(x(3)-x(2)) + &
         (y(3)-y(2))*(y(3)-y(2)) + &
         (z(3)-z(2))*(z(3)-z(2))
    c2 = (x(3)-x(1))*(x(3)-x(1)) + &
         (y(3)-y(1))*(y(3)-y(1)) + &
         (z(3)-z(1))*(z(3)-z(1))
    get_height = sqrt(abs(a2 - ((c2 - b2 + a2) / 2*sqrt(c2))**2))
end function get_height

function get_area(x, y, z)
    implicit none

    real(kind=dp) :: x(3), y(3), z(3), xp(3)
    real(kind=dp) :: get_area
    real(kind=dp) :: h, d
    h = get_height(x, y, z)
    d = sqrt((x(3)-x(1))*(x(3)-x(1)) + &
             (y(3)-y(1))*(y(3)-y(1)) + &
             (z(3)-z(1))*(z(3)-z(1)))
    get_area = h*d/2
end function get_area

end module mod_bathy_compute
