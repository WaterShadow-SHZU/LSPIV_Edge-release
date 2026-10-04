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

program manual_velocity

    use lspiv_parameter

    implicit none

    real(kind=dp), dimension(:), allocatable :: x1, y1, x2, y2, dt, velx, vely, vel
    integer :: lu, i, compt, ios
    character (len=:), allocatable :: in_file, out_file

    allocate(character(len=len_trim(outputs_dir)+len_trim(manual_tracking)+1) :: in_file)
    in_file = trim(outputs_dir)//'/'//trim(manual_tracking)
    allocate(character(len=len_trim(outputs_dir)+len_trim(manual_vel)+1) :: out_file)
    out_file = trim(outputs_dir)//'/'//trim(manual_vel)
    open(newunit=lu,file=in_file,status='old')
    ! header, nothing to do
    read(lu,*,iostat=ios)
    ! read the number of couples
    read(lu,*,iostat=ios) compt
    ! another header, nothing to do
    read(lu,*,iostat=ios)
    ! memory allocation
    allocate(x1(compt),y1(compt),x2(compt),y2(compt),dt(compt), velx(compt), vely(compt), vel(compt))
    do i=1, compt
        read(lu,*,iostat=ios) x1(i), y1(i), x2(i), y2(i), dt(i)
    end do
    close(lu)

    call sub_velocity(x1(:), y1(:), x2(:), y2(:), dt(:), velx(:), vely(:), vel(:))

    ! Write output file
    open(newunit=lu,file=out_file,form='formatted',status='unknown')
    do i=1, compt
        if (dt(i) < 0.0) then
            write(lu,*) x2(i), y2(i), velx(i), vely(i)
        else
            write(lu,*) x1(i), y1(i), velx(i), vely(i)
        end if
    end do
    close(lu)

    deallocate(x1, y1, x2, y2, dt, velx, vely)

    contains

    subroutine sub_velocity(x1, y1, x2, y2, dt, velx, vely, vel)
        real(kind=dp), intent(in), dimension(:) :: x1, x2, y1, y2, dt
        real(kind=dp), intent(inout), dimension(:) :: velx, vely, vel
        integer :: i

        do i=1, size(dt)
            velx(i) = (x2(i)-x1(i))/dt(i)
            vely(i) = (y2(i)-y1(i))/dt(i)
            vel(i) = sqrt((x2(i)-x1(i))**2 + (y2(i)-y1(i))**2)/abs(dt(i))
        end do

    end subroutine sub_velocity

end program manual_velocity
