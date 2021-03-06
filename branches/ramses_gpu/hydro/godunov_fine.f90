!###########################################################
!###########################################################
!###########################################################
!###########################################################
subroutine godunov_fine(ilevel)
  use amr_commons
  use hydro_commons
  use acc_commons
  implicit none
  integer::ilevel
  !--------------------------------------------------------------------------
  ! This routine is a wrapper to the second order Godunov solver.
  ! Small grids (2x2x2) are gathered from level ilevel and sent to the
  ! hydro solver. On entry, hydro variables are gathered from array uold.
  ! On exit, unew has been updated. 
  !--------------------------------------------------------------------------
  integer::i,j,ivar,nx_ok,nx_cell,ngrid_ok,ilev,igrid,ncache,ngrid,levelup,iskip
  integer,dimension(1:nvector)::ind_grid
  integer,dimension(1:nlevelmax)::ngroup
  integer,allocatable,dimension(:)::isort
  integer nrefinedu
  integer nrefinedg
  integer countaux
  integer npatches

  if(numbtot(1,ilevel)==0)return
  if(static)return
  if(verbose)write(*,111)ilevel

  ! Local constants
  levelup=max(ilevel-3,1)
  ncache=active(ilevel)%ngrid

  ! Sort grids in large patches
  allocate(isort(ncache))
  call sort_group_grid(isort,ilevel,levelup,ngroup,ncache)

  ! Calculate the total number of cells 
  nrefinedu = 0
  nrefinedg = 0
  do ilev=levelup,ilevel-1
     nx_ok=2**(ilevel-1-ilev)
     ngrid_ok=nx_ok**ndim
     nx_cell=2*nx_ok 
     npatches = ngroup(ilev)/ngrid_ok

     nrefinedu = nrefinedu + npatches*(nx_cell+4)**3*nvar
     nrefinedg = nrefinedg + npatches*(nx_cell+4)**3*ndim
  enddo
  !WRITE(*,*)"Mesh total size: ", nrefinedu, nrefinedg

  ! Allocate auxiliary arrays
  allocate(uloc_tot(nrefinedu))
  allocate(gloc_tot(nrefinedg)) 
  ucount = 1
  gcount = 1
  
!$acc data pcopyout(unew)
  countaux=0
  iskip=1
  do ilev=levelup,ilevel-1
     nx_ok=2**(ilevel-1-ilev)
     ngrid_ok=nx_ok**ndim
     nx_cell=2*nx_ok 
     write(*,*)'=========================================='
     write(*,999)ilev+1,ngroup(ilev)/ngrid_ok,ngrid_ok
999 format(' Level',I3,' found ',I6,' groups of size ',I2,'')
     if(ngroup(ilev)>0)then
        write(*,*)'=========================================='
        do i=iskip,iskip+ngroup(ilev)-1,ngrid_ok
           !!write(*,*)(active(ilevel)%igrid(isort(i+j-1)),j=1,ngrid_ok)
888 format(16(I3,1X))
           igrid=active(ilevel)%igrid(isort(i))
           call fill_hydro_grid(igrid,nx_cell,ilevel)           
        end do
        iskip=iskip+ngroup(ilev)
     endif
  end do
  write(*,*)'=========================================='
!$acc end data

!!  do igrid=1,ncache,nvector
!!     ngrid=MIN(nvector,ncache-igrid+1)
!!     do i=1,ngrid
!!        ind_grid(i)=active(ilevel)%igrid(igrid+i-1)
!!     end do
!!     call godfine1(ind_grid,ngrid,ilevel)
!!  end do

  ! Deallocate local arrays
  deallocate(isort)
  deallocate(uloc_tot)
  deallocate(gloc_tot) 

111 format('   Entering godunov_fine for level ',i2)

end subroutine godunov_fine
!###########################################################
!###########################################################
!###########################################################
!###########################################################
subroutine sort_group_grid(isort_fin,ilevel,levelup,ngroup,ncache)
  use amr_commons
  use hydro_commons
  implicit none
  integer::ilevel,levelup,ncache
  integer,dimension(1:ncache)::isort_fin
  integer,dimension(1:nlevelmax)::ngroup
  !--------------------------------------------------------------------------
  !--------------------------------------------------------------------------
  integer::i,j,ivar,igrid,ngrid,bit_length,ncode,nxny,nx_loc
  integer::ifirst,ilast,iskip,ngrid_ok,i_new,ifin,ilevelup
  real(dp),dimension(1:nvector,1:ndim)::x
  real(qdp),dimension(1:nvector)::order_min,order_max
  integer,dimension(1:nvector)::ix,iy,iz,ind_grid

  real(qdp),dimension(1:ncache)::hkeys
  integer,dimension(1:ncache)::isort,isort_new,inext,done

  real(qdp)::hstep,hcomp,hcurr
  real(kind=8)::bscale
  real(dp)::scale

  ! Local constants
  nxny=nx*ny
  nx_loc=icoarse_max-icoarse_min+1
  scale=boxlen/dble(nx_loc)

  ! Loop over active grids by vector sweeps
  ifin=0; done=0
  ngroup=0

  do ilevelup=levelup,ilevel-1

     bscale=2**ilevelup
     ncode=nx_loc*bscale
     do bit_length=1,32
        ncode=ncode/2
        if(ncode<=1) exit
     end do
     if(bit_length==32) then
        write(*,*)'Error in cmp_minmaxorder'
#ifndef WITHOUTMPI
        call MPI_ABORT(MPI_COMM_WORLD,1,info)
#else
        stop
#endif
     end if
     
!!$     write(*,*)'level up=',ilevelup
!!$     write(*,*)'bit length=',bit_length
     
     ! Assign hilbert keys at ilevel-2 to the grid positions and sort them
     do i=1,ncache
        igrid=active(ilevel)%igrid(i)
        x(1,1)=(xg(igrid,1)-dble(icoarse_min))
#if NDIM>1
        x(1,2)=(xg(igrid,2)-dble(jcoarse_min))
#endif
#if NDIM>2
        x(1,3)=(xg(igrid,3)-dble(kcoarse_min))
#endif
        
        ix(1)=int(x(1,1)*bscale)
#if NDIM>1
        iy(1)=int(x(1,2)*bscale)
#endif
#if NDIM>2
        iz(1)=int(x(1,3)*bscale)
#endif
        
#if NDIM==1
        call hilbert1d(ix,order_min,1)
#endif
#if NDIM==2
        call hilbert2d(ix,iy,order_min,bit_length,1)
#endif
#if NDIM==3
        call hilbert3d(ix,iy,iz,order_min,bit_length,1)
#endif
        hkeys(i)=order_min(1)
     end do

     call quick_sort(hkeys,isort,ncache)

     ! Compute scan for ilevel-2 grids
     j=1
     inext(j)=1
     hcomp=hkeys(j)
     do i=2,ncache
        hcurr=hkeys(i)
        if(hcurr.eq.hcomp)then
           inext(j)=inext(j)+1
        else
           j=j+1
           inext(j)=1
           hcomp=hcurr
        endif
     end do
     
     ngrid_ok=(2**(ilevel-1-ilevelup))**ndim
     ifirst=1
     iskip=1
     do i=1,j
        if(inext(i)==ngrid_ok)then
           do i_new=1,inext(i)
              isort_new(ifirst-1+i_new)=isort(iskip-1+i_new)
           end do
           ifirst=ifirst+inext(i)
        endif
        iskip=iskip+inext(i)
     end do
     do i=1,ifirst-1
        if(done(isort_new(i))==0)then
           ifin=ifin+1
           ngroup(ilevelup)=ngroup(ilevelup)+1
           isort_fin(ifin)=isort_new(i)
           done(isort_new(i))=1
        endif
     end do
     iskip=1
     do i=1,j
        if(inext(i).NE.ngrid_ok)then
           do i_new=1,inext(i)
              isort_new(ifirst-1+i_new)=isort(iskip-1+i_new)
           end do
           ifirst=ifirst+inext(i)
        endif
        iskip=iskip+inext(i)
     end do

  end do
  
end subroutine sort_group_grid
!###########################################################
!###########################################################
!###########################################################
!###########################################################
subroutine set_unew(ilevel)
  use amr_commons
  use hydro_commons
  implicit none
  integer::ilevel
  !--------------------------------------------------------------------------
  ! This routine sets array unew to its initial value uold before calling
  ! the hydro scheme. unew is set to zero in virtual boundaries.
  !--------------------------------------------------------------------------
  integer::i,ivar,ind,icpu,iskip
  real(dp)::d,u,v,w,e

  WRITE(*,*)"ILEVEL, NGRID ",ilevel,active(ilevel)%ngrid
  if(numbtot(1,ilevel)==0)return
  if(verbose)write(*,111)ilevel

  ! Set unew to uold for myid cells
  do ind=1,twotondim
     iskip=ncoarse+(ind-1)*ngridmax

     do ivar=1,nvar
        do i=1,active(ilevel)%ngrid
           unew(active(ilevel)%igrid(i)+iskip,ivar) = uold(active(ilevel)%igrid(i)+iskip,ivar)
        end do
     end do
        !!!do i=1,active(ilevel)%ngrid
        !!!   write(200,*)unew(active(ilevel)%igrid(i)+iskip,5)
        !!!end do
     if(pressure_fix)then
        do i=1,active(ilevel)%ngrid
           divu(active(ilevel)%igrid(i)+iskip) = 0.0
        end do
        do i=1,active(ilevel)%ngrid
           d=uold(active(ilevel)%igrid(i)+iskip,1)
           u=0.0; v=0.0; w=0.0
           if(ndim>0)u=uold(active(ilevel)%igrid(i)+iskip,2)/d
           if(ndim>1)v=uold(active(ilevel)%igrid(i)+iskip,3)/d
           if(ndim>2)w=uold(active(ilevel)%igrid(i)+iskip,4)/d
           e=uold(active(ilevel)%igrid(i)+iskip,ndim+2)-0.5*d*(u**2+v**2+w**2)
           enew(active(ilevel)%igrid(i)+iskip)=e
        end do
     end if
  end do

  ! Set unew to 0 for virtual boundary cells
  do icpu=1,ncpu
  do ind=1,twotondim
     iskip=ncoarse+(ind-1)*ngridmax
     do ivar=1,nvar
        do i=1,reception(icpu,ilevel)%ngrid
           unew(reception(icpu,ilevel)%igrid(i)+iskip,ivar)=0.0
        end do
     end do
     if(pressure_fix)then
        do i=1,reception(icpu,ilevel)%ngrid
           divu(reception(icpu,ilevel)%igrid(i)+iskip) = 0.0
           enew(reception(icpu,ilevel)%igrid(i)+iskip) = 0.0
        end do
     end if
  end do
  end do

  !!!close(200)
111 format('   Entering set_unew for level ',i2)

end subroutine set_unew
!###########################################################
!###########################################################
!###########################################################
!###########################################################
subroutine set_uold(ilevel)
  use amr_commons
  use hydro_commons
  use poisson_commons
  implicit none
  integer::ilevel
  !--------------------------------------------------------------------------
  ! This routine sets array uold to its new value unew after the
  ! hydro step.
  !--------------------------------------------------------------------------
  integer::i,ivar,ind,iskip,nx_loc
  real(dp)::scale,d,u,v,w
  real(dp)::e_kin,e_cons,e_prim,e_trunc,div,dx,fact,d_old

  if(numbtot(1,ilevel)==0)return
  if(verbose)write(*,111)ilevel

  nx_loc=icoarse_max-icoarse_min+1
  scale=boxlen/dble(nx_loc)
  dx=0.5d0**ilevel*scale

  ! Add gravity source term at time t with half time step
  if(poisson)then
     do ind=1,twotondim
        iskip=ncoarse+(ind-1)*ngridmax
        do i=1,active(ilevel)%ngrid
           d=unew(active(ilevel)%igrid(i)+iskip,1)
           u=0.0; v=0.0; w=0.0
           if(ndim>0)u=unew(active(ilevel)%igrid(i)+iskip,2)/d
           if(ndim>1)v=unew(active(ilevel)%igrid(i)+iskip,3)/d
           if(ndim>2)w=unew(active(ilevel)%igrid(i)+iskip,4)/d
           e_kin=0.5*d*(u**2+v**2+w**2)
           e_prim=unew(active(ilevel)%igrid(i)+iskip,ndim+2)-e_kin
           d_old=uold(active(ilevel)%igrid(i)+iskip,1)
           fact=d_old/d*0.5*dtnew(ilevel)
           if(ndim>0)then
              u=u+f(active(ilevel)%igrid(i)+iskip,1)*fact
              unew(active(ilevel)%igrid(i)+iskip,2)=d*u
           endif
           if(ndim>1)then
              v=v+f(active(ilevel)%igrid(i)+iskip,2)*fact
              unew(active(ilevel)%igrid(i)+iskip,3)=d*v
           end if
           if(ndim>2)then
              w=w+f(active(ilevel)%igrid(i)+iskip,3)*fact
              unew(active(ilevel)%igrid(i)+iskip,4)=d*w
           endif
           e_kin=0.5*d*(u**2+v**2+w**2)
           unew(active(ilevel)%igrid(i)+iskip,ndim+2)=e_prim+e_kin
        end do
     end do
  end if

  ! Set uold to unew for myid cells
  do ind=1,twotondim
     iskip=ncoarse+(ind-1)*ngridmax
     do ivar=1,nvar
        do i=1,active(ilevel)%ngrid
           uold(active(ilevel)%igrid(i)+iskip,ivar) = unew(active(ilevel)%igrid(i)+iskip,ivar)
        end do
     end do
     if(pressure_fix)then
        fact=(gamma-1.0d0)
        do i=1,active(ilevel)%ngrid
           d=uold(active(ilevel)%igrid(i)+iskip,1)
           u=0.0; v=0.0; w=0.0
           if(ndim>0)u=uold(active(ilevel)%igrid(i)+iskip,2)/d
           if(ndim>1)v=uold(active(ilevel)%igrid(i)+iskip,3)/d
           if(ndim>2)w=uold(active(ilevel)%igrid(i)+iskip,4)/d
           e_kin=0.5*d*(u**2+v**2+w**2)
           e_cons=uold(active(ilevel)%igrid(i)+iskip,ndim+2)-e_kin
           e_prim=enew(active(ilevel)%igrid(i)+iskip)*(1.0d0+fact* &
                & divu(active(ilevel)%igrid(i)+iskip))! Note: here divu=-div.u*dt
           div=abs(divu(active(ilevel)%igrid(i)+iskip))*dx/dtnew(ilevel)
           e_trunc=beta_fix*d*max(div,3.0*hexp*dx)**2
           if(e_cons<e_trunc)then
              uold(active(ilevel)%igrid(i)+iskip,ndim+2)=e_prim+e_kin
           end if
        end do
     end if
  end do

111 format('   Entering set_uold for level ',i2)

end subroutine set_uold
!###########################################################
!###########################################################
!###########################################################
!###########################################################
subroutine fill_hydro_grid(igrid,nxp,ilevel)
  use amr_commons
  use hydro_commons
  use poisson_commons
  use acc_commons
  implicit none
  integer::igrid,ilevel,nxp
  integer::i1,j1,k1,l1,m1,ivar
  integer:: cindex
  !
  ! This routine fills up a Cartesian grid from AMR data 
  ! and send it to the hydro kernel
  !
#if NDIM==1
!!!  real(dp),dimension(-1:nxp+2,1:nvar)::uloc
!!!  real(dp),dimension(-1:nxp+2,1:ndim)::gloc
  real(dp),dimension(1:nxp+1,1:nvar,1:ndim)::flux
  real(dp),dimension(1:nxp+1,1:2,1:ndim)::tmp
  real(dp),dimension(nxp)::divuloc
  real(dp),dimension(nxp)::enewloc
#endif
#if NDIM==2
!!!  real(dp),dimension(-1:nxp+2,-1:nxp+2,1:nvar)::uloc
!!!  real(dp),dimension(-1:nxp+2,-1:nxp+2,1:ndim)::gloc
  real(dp),dimension(1:nxp+1,1:nxp+1,1:nvar,1:ndim)::flux
  real(dp),dimension(1:nxp+1,1:nxp+1,1:2,1:ndim)::tmp
  real(dp),dimension(nxp,nxp)::divuloc
  real(dp),dimension(nxp,nxp)::enewloc
#endif
#if NDIM==3
!!!  real(dp),dimension(-1:nxp+2,-1:nxp+2,-1:nxp+2,1:nvar)::uloc
!!!  real(dp),dimension(-1:nxp+2,-1:nxp+2,-1:nxp+2,1:ndim)::gloc
  real(dp),dimension(1:nxp+1,1:nxp+1,1:nxp+1,1:nvar,1:ndim)::flux
  real(dp),dimension(1:nxp+1,1:nxp+1,1:nxp+1,1:2,1:ndim)::tmp
  real(dp),dimension(nxp,nxp,nxp)::divuloc
  real(dp),dimension(nxp,nxp,nxp)::enewloc
#endif

  integer::nx_loc,i,j,k,i0,j0,k0,idim,ivar
  real(dp)::dx,scale,dx_loc,dx_box
  real(dp),dimension(1:nvector,1:ndim)::xx_dp
  real(dp),dimension(1:ndim)::box_xmin
  integer,dimension(1:nvector)::cell_index,cell_levl
  integer :: ucount0, ucount1
  integer :: gcount0, gcount1
  integer :: uindex, gindex, bindex
  integer :: nxp4
  integer :: iiii
!CLAU

  ! Mesh spacing at that level
  nx_loc=icoarse_max-icoarse_min+1
  scale=boxlen/dble(nx_loc)
  dx=0.5D0**ilevel
  dx_box=nxp*dx
  dx_loc=scale*dx
  nxp4 = nxp+4
 
  ! Compute box coordinates in normalized unites
  do idim=1,ndim
     box_xmin(idim)=int(xg(igrid,idim)/dx_box)*dx_box
  end do

  ! Update main patch counters

  ucount0 = ucount
  gcount0 = gcount

  ! Compute cell coordinate
  do k=-1,nxp+2
     xx_dp(1,3) = box_xmin(3) + (dble(k)-0.5)*dx
#if NDIM>1
     do j=-1,nxp+2
        xx_dp(1,2) = box_xmin(2) + (dble(j)-0.5)*dx
#endif
#if NDIM>2
        do i=-1,nxp+2
           xx_dp(1,1) = box_xmin(1) + (dble(i)-0.5)*dx
#endif
           ! Compute cell index
           call hydro_get_cell_index(cell_index,cell_levl,xx_dp,ilevel,1)
           ! Store hydro variable in local Cartesian grid
           bindex = (ucount0-1) + ( i+2 + nxp4*(j+1) + nxp4*nxp4*(k+1) )
           do ivar=1,nvar
              uindex = bindex + (ivar-1)*nxp4**3
              uloc_tot(uindex) = uold(cell_index(1),ivar)
              ucount = ucount+1
           end do
!!! CHECK INDICES: CRASHES WITH SEGFAULT
           !do idim=1,ndim
           !   gindex = bindex + (idim-1)*nxp4**3
           !   gloc_tot(gindex) = 0.0
           !   gcount = gcount+1
           !   if(poisson)gloc_tot(gcount) = f(cell_index(1),idim)
           !end do
#if NDIM>2
        end do
#endif
#if NDIM>1
     end do
#endif
  end do

  ucount1 = ucount-1
  gcount1 = gcount-1


!CLAUACC
!!!!!$acc data copy(uloc,gloc,dtnew) pcopyout(divuloc,enewloc)&
!$acc data pcreate (flux, tmp, divuloc, enewloc, uloc_tot, gloc_tot) pcopyin(cell_index)
!!!!!$acc&     pcreate(flux,tmp)
!!!!$acc pcopyout(flux,tmp)

!$acc update device(uloc_tot(ucount0:ucount1), gloc_tot(gcount0:gcount1)) !!!!!!async(acount)

!$acc parallel loop collapse(5)
  do m1=1,ndim
  do l1=1,nvar
  do k1=1,nxp+1
  do j1=1,nxp+1
  do i1=1,nxp+1
     flux(i1,j1,k1,l1,m1)=0.0
  enddo
  enddo
  enddo
  enddo
  enddo
!$acc end parallel loop
!$acc parallel loop collapse(5)
  do m1=1,ndim
  do l1=1,2
  do k1=1,nxp+1
  do j1=1,nxp+1
  do i1=1,nxp+1
     tmp(i1,j1,k1,l1,m1)=0.0
  enddo
  enddo
  enddo
  enddo
  enddo
!$acc end parallel loop


! Compute flux using second-order Godunov method

  call unsplit_gpu_2d(uloc_tot(ucount0:ucount1),gloc_tot(gcount0:gcount1),flux,tmp,dx_loc,nxp,dtnew(ilevel))

!$acc parallel loop 

  do k=1,nxp
#if NDIM>1
     do j=1,nxp
#endif
#if NDIM>2
        do i=1,nxp           
#endif
           xx_dp(1,1) = box_xmin(1) + (dble(i)-0.5)*dx
           xx_dp(1,2) = box_xmin(2) + (dble(j)-0.5)*dx
           xx_dp(1,3) = box_xmin(3) + (dble(k)-0.5)*dx
           call hydro_get_cell_index(cell_index,cell_levl,xx_dp,ilevel,1)
           do ivar=1,nvar
#if NDIM==1
           uindex = (ucount0-1) + (i+2) + (ivar-1)*nxp4
#endif
#if NDIM==2
           uindex = (ucount0-1) + (i+2) + (j+1)*nxp4 + (ivar-1)*nxp4**2
#endif
#if NDIM==3
           uindex = (ucount0-1) + ((i+2) + (j+1)*nxp4 + (k+1)*nxp4*nxp4) + (ivar-1)*nxp4**3
#endif
           do idim=1,ndim
              i0=0; j0=0; k0=0
              if(idim==1)i0=1
              if(idim==2)j0=1
              if(idim==3)k0=1
              ! Update conservative variables new state vector
              uloc_tot(uindex)  = uloc_tot(uindex) + (flux(i,j,k,ivar,idim)-flux(i+i0,j+j0,k+k0,ivar,idim))
           end do

           unew(cell_index(1),ivar)  = uloc_tot(uindex) 

              ! Update velocity divergence and internal energy
!!CLAU: TO BE ASYNCED
!!              if(pressure_fix)then
!!#if NDIM==1
!!                 divuloc(i) = (tmp(i,1,idim)-tmp(i+i0,1,idim))
!!                 enewloc(i) = (tmp(i,2,idim)-tmp(i+i0,2,idim))
!!#endif
!!#if NDIM==2
!!                 divuloc(i,j) = (tmp(i,j,1,idim)-tmp(i+i0,j+j0,1,idim))
!!                 enewloc(i,j) = (tmp(i,j,2,idim)-tmp(i+i0,j+j0,2,idim))
!!#endif
!!#if NDIM==3
!!                 divuloc(i,j,k) = (tmp(i,j,k,1,idim)-tmp(i+i0,j+j0,k+k0,1,idim))
!!                 enewloc(i,j,k) = (tmp(i,j,k,2,idim)-tmp(i+i0,j+j0,k+k0,2,idim))
!!#endif
!!              end if
           end do
#if NDIM>2
        end do
#endif
#if NDIM>1
     end do
#endif
  end do
!$acc end parallel loop
!$acc end data


!! TO BE REMOVED!!!!!!!!!!!!!!!!!!!!!!
     if(pressure_fix)then
     do i=1,nxp
        do j=1,nxp
           do k=1,nxp
           xx_dp(1,1) = box_xmin(1) + (dble(i)-0.5)*dx
           xx_dp(1,2) = box_xmin(2) + (dble(j)-0.5)*dx
           xx_dp(1,3) = box_xmin(3) + (dble(k)-0.5)*dx
           call hydro_get_cell_index(cell_index,cell_levl,xx_dp,ilevel,1)
                   divu(cell_index(1)) = 0.0 
                   enew(cell_index(1)) = 0.0 
           enddo
        enddo
      enddo
      endif
  !CLOSE(300)
  !READ(*,*)iiii

end subroutine fill_hydro_grid
!###########################################################
!###########################################################
!###########################################################
!###########################################################
subroutine hydro_get_cell_index(cell_index,cell_levl,xpart,ilevel,np)
  use amr_commons
  implicit none
  integer::np,ilevel
  integer,dimension(1:nvector)::cell_index,cell_levl
  real(dp),dimension(1:nvector,1:ndim)::xpart
  !----------------------------------------------------------------------------
  ! This routine returns the index of the cell, at maximum level
  ! ilevel, in which the input particle sits.
  ! Warning: coordinates are supposed to be in normalized units
  ! for the inner computational box so always between 0 and 1.
  !----------------------------------------------------------------------------
  real(dp)::xx,yy,zz
  integer::i,j,ii,jj=0,kk=0,ind,iskip,igrid,ind_cell,igrid0
  ind_cell=0
  do i=1,np
     ii=0; jj=0; kk=0
     xx=xpart(i,1)
     if(xx<0d0)xx=xx+dble(nx)
     if(xx>=dble(nx))xx=xx-dble(nx)
     ii=int(xx)
#if NDIM>1
     yy=xpart(i,2)
     if(yy<0d0)yy=yy+dble(ny)
     if(yy>=dble(ny))yy=yy-dble(ny)
     jj=int(yy)
#endif
#if NDIM>2
     zz=xpart(i,3)
     if(zz<0d0)zz=zz+dble(nz)
     if(zz>=dble(nz))zz=zz-dble(nz)
     kk=int(zz)
#endif
     igrid=son(1+ii+jj*nx+kk*nx*ny)
     do j=1,ilevel
        ii=0; jj=0; kk=0
        if(xx>xg(igrid,1))ii=1
#if NDIM>1
        if(yy>xg(igrid,2))jj=1
#endif
#if NDIM>2
        if(zz>xg(igrid,3))kk=1
#endif
        ind=1+ii+2*jj+4*kk
        iskip=ncoarse+(ind-1)*ngridmax
        ind_cell=iskip+igrid
        igrid=son(ind_cell)
        if(igrid==0.or.j==ilevel)exit
     end do
     cell_index(i)=ind_cell
     cell_levl(i)=j
  end do
end subroutine hydro_get_cell_index
!###########################################################
!###########################################################
!###########################################################
!###########################################################
subroutine godfine1(ind_grid,ncache,ilevel)
  use amr_commons
  use hydro_commons
  use poisson_commons
  implicit none
  integer::ilevel,ncache
  integer,dimension(1:nvector)::ind_grid
  !-------------------------------------------------------------------
  ! This routine gathers first hydro variables from neighboring grids
  ! to set initial conditions in a 6x6x6 grid. It interpolate from
  ! coarser level missing grid variables. It then calls the
  ! Godunov solver that computes fluxes. These fluxes are zeroed at 
  ! coarse-fine boundaries, since contribution from finer levels has
  ! already been taken into account. Conservative variables are updated 
  ! and stored in array unew(:), both at the current level and at the 
  ! coarser level if necessary.
  !-------------------------------------------------------------------
  integer ,dimension(1:nvector,1:threetondim     ),save::nbors_father_cells
  integer ,dimension(1:nvector,1:twotondim       ),save::nbors_father_grids
  integer ,dimension(1:nvector,0:twondim         ),save::ibuffer_father
  real(dp),dimension(1:nvector,0:twondim  ,1:nvar),save::u1
  real(dp),dimension(1:nvector,1:twotondim,1:nvar),save::u2
  real(dp),dimension(1:nvector,0:twondim  ,1:ndim),save::g1=0.0d0
  real(dp),dimension(1:nvector,1:twotondim,1:ndim),save::g2=0.0d0

  real(dp),dimension(1:nvector,iu1:iu2,ju1:ju2,ku1:ku2,1:nvar),save::uloc
  real(dp),dimension(1:nvector,iu1:iu2,ju1:ju2,ku1:ku2,1:ndim),save::gloc=0.0d0
  real(dp),dimension(1:nvector,if1:if2,jf1:jf2,kf1:kf2,1:nvar,1:ndim),save::flux
  real(dp),dimension(1:nvector,if1:if2,jf1:jf2,kf1:kf2,1:2,1:ndim),save::tmp
  logical ,dimension(1:nvector,iu1:iu2,ju1:ju2,ku1:ku2),save::ok

  integer,dimension(1:nvector),save::igrid_nbor,ind_cell,ind_buffer,ind_exist,ind_nexist

  integer::i,j,ivar,idim,ind_son,ind_father,iskip,nbuffer,ibuffer
  integer::i0,j0,k0,i1,j1,k1,i2,j2,k2,i3,j3,k3,nx_loc,nb_noneigh,nexist
  integer::i1min,i1max,j1min,j1max,k1min,k1max
  integer::i2min,i2max,j2min,j2max,k2min,k2max
  integer::i3min,i3max,j3min,j3max,k3min,k3max
  real(dp)::dx,scale,oneontwotondim

  oneontwotondim = 1.d0/dble(twotondim)

  ! Mesh spacing in that level
  nx_loc=icoarse_max-icoarse_min+1
  scale=boxlen/dble(nx_loc)
  dx=0.5D0**ilevel*scale

  ! Integer constants
  i1min=0; i1max=0; i2min=0; i2max=0; i3min=1; i3max=1
  j1min=0; j1max=0; j2min=0; j2max=0; j3min=1; j3max=1
  k1min=0; k1max=0; k2min=0; k2max=0; k3min=1; k3max=1
  if(ndim>0)then
     i1max=2; i2max=1; i3max=2
  end if
  if(ndim>1)then
     j1max=2; j2max=1; j3max=2
  end if
  if(ndim>2)then
     k1max=2; k2max=1; k3max=2
  end if

  !------------------------------------------
  ! Gather 3^ndim neighboring father cells
  !------------------------------------------
  do i=1,ncache
     ind_cell(i)=father(ind_grid(i))
  end do
  call get3cubefather(ind_cell,nbors_father_cells,nbors_father_grids,ncache,ilevel)
  
  !---------------------------
  ! Gather 6x6x6 cells stencil
  !---------------------------
  ! Loop over 3x3x3 neighboring father cells
  do k1=k1min,k1max
  do j1=j1min,j1max
  do i1=i1min,i1max
     
     ! Check if neighboring grid exists
     nbuffer=0
     nexist=0
     ind_father=1+i1+3*j1+9*k1
     do i=1,ncache
        igrid_nbor(i)=son(nbors_father_cells(i,ind_father))
        if(igrid_nbor(i)>0) then
           nexist=nexist+1
           ind_exist(nexist)=i
        else
          nbuffer=nbuffer+1
          ind_nexist(nbuffer)=i
          ind_buffer(nbuffer)=nbors_father_cells(i,ind_father)
        end if
     end do
     
     ! If not, interpolate hydro variables from parent cells
     if(nbuffer>0)then
        call getnborfather(ind_buffer,ibuffer_father,nbuffer,ilevel)
        do j=0,twondim
           do ivar=1,nvar
              do i=1,nbuffer
                 u1(i,j,ivar)=uold(ibuffer_father(i,j),ivar)
              end do
           end do
        end do
        call interpol_hydro(u1,u2,nbuffer)
     endif

     ! Loop over 2x2x2 cells
     do k2=k2min,k2max
     do j2=j2min,j2max
     do i2=i2min,i2max

        ind_son=1+i2+2*j2+4*k2
        iskip=ncoarse+(ind_son-1)*ngridmax
        do i=1,nexist
           ind_cell(i)=iskip+igrid_nbor(ind_exist(i))
        end do
        
        i3=1; j3=1; k3=1
        if(ndim>0)i3=1+2*(i1-1)+i2
        if(ndim>1)j3=1+2*(j1-1)+j2
        if(ndim>2)k3=1+2*(k1-1)+k2
        
        ! Gather hydro variables
        do ivar=1,nvar
           do i=1,nexist
              uloc(ind_exist(i),i3,j3,k3,ivar)=uold(ind_cell(i),ivar)
           end do
           do i=1,nbuffer
              uloc(ind_nexist(i),i3,j3,k3,ivar)=u2(i,ind_son,ivar)
           end do
        end do
        
        ! Gather gravitational acceleration
        if(poisson)then
           do idim=1,ndim
              do i=1,nexist
                 gloc(ind_exist(i),i3,j3,k3,idim)=f(ind_cell(i),idim)
              end do
              ! Use straight injection for buffer cells
              do i=1,nbuffer
                 gloc(ind_nexist(i),i3,j3,k3,idim)=f(ibuffer_father(i,0),idim)
              end do
           end do
        end if
        
        ! Gather refinement flag
        do i=1,nexist
           ok(ind_exist(i),i3,j3,k3)=son(ind_cell(i))>0
        end do
        do i=1,nbuffer
           ok(ind_nexist(i),i3,j3,k3)=.false.
        end do
        
     end do
     end do
     end do
     ! End loop over cells

  end do
  end do
  end do
  ! End loop over neighboring grids

  !-----------------------------------------------
  ! Compute flux using second-order Godunov method
  !-----------------------------------------------
  call unsplit(uloc,gloc,flux,tmp,dx,dx,dx,dtnew(ilevel),ncache)

  !------------------------------------------------
  ! Reset flux along direction at refined interface    
  !------------------------------------------------
  do idim=1,ndim
     i0=0; j0=0; k0=0
     if(idim==1)i0=1
     if(idim==2)j0=1
     if(idim==3)k0=1
     do k3=k3min,k3max+k0
     do j3=j3min,j3max+j0
     do i3=i3min,i3max+i0
        do ivar=1,nvar
           do i=1,ncache
              if(ok(i,i3-i0,j3-j0,k3-k0) .or. ok(i,i3,j3,k3))then
                 flux(i,i3,j3,k3,ivar,idim)=0.0d0
              end if
           end do
        end do
        if(pressure_fix)then
        do ivar=1,2
           do i=1,ncache
              if(ok(i,i3-i0,j3-j0,k3-k0) .or. ok(i,i3,j3,k3))then
                 tmp (i,i3,j3,k3,ivar,idim)=0.0d0
              end if
           end do
        end do
        end if
     end do
     end do
     end do
  end do
  !--------------------------------------
  ! Conservative update at level ilevel
  !--------------------------------------
  do idim=1,ndim
     i0=0; j0=0; k0=0
     if(idim==1)i0=1
     if(idim==2)j0=1
     if(idim==3)k0=1
     do k2=k2min,k2max
     do j2=j2min,j2max
     do i2=i2min,i2max
        ind_son=1+i2+2*j2+4*k2
        iskip=ncoarse+(ind_son-1)*ngridmax
        do i=1,ncache
           ind_cell(i)=iskip+ind_grid(i)
        end do
        i3=1+i2
        j3=1+j2
        k3=1+k2
        ! Update conservative variables new state vector
        do ivar=1,nvar
           do i=1,ncache
              unew(ind_cell(i),ivar)=unew(ind_cell(i),ivar)+ &
                   & (flux(i,i3   ,j3   ,k3   ,ivar,idim) &
                   & -flux(i,i3+i0,j3+j0,k3+k0,ivar,idim))
           end do
        end do
        if(pressure_fix)then
        ! Update velocity divergence
        do i=1,ncache
           divu(ind_cell(i))=divu(ind_cell(i))+ &
                & (tmp(i,i3   ,j3   ,k3   ,1,idim) &
                & -tmp(i,i3+i0,j3+j0,k3+k0,1,idim))
        end do
        ! Update internal energy
        do i=1,ncache
           enew(ind_cell(i))=enew(ind_cell(i))+ &
                & (tmp(i,i3   ,j3   ,k3   ,2,idim) &
                & -tmp(i,i3+i0,j3+j0,k3+k0,2,idim))
        end do
        end if
     end do
     end do
     end do
  end do

  !--------------------------------------
  ! Conservative update at level ilevel-1
  !--------------------------------------
  ! Loop over dimensions
  do idim=1,ndim
     i0=0; j0=0; k0=0
     if(idim==1)i0=1
     if(idim==2)j0=1
     if(idim==3)k0=1
     
     !----------------------
     ! Left flux at boundary
     !----------------------     
     ! Check if grids sits near left boundary
     ! and gather neighbor father cells index
     nb_noneigh=0
     do i=1,ncache
        if (son(nbor(ind_grid(i),2*idim-1))==0) then
           nb_noneigh = nb_noneigh + 1
           ind_buffer(nb_noneigh) = nbor(ind_grid(i),2*idim-1)
           ind_cell(nb_noneigh) = i
        end if
     end do
     ! Conservative update of new state variables
     do ivar=1,nvar
        ! Loop over boundary cells
        do k3=k3min,k3max-k0
        do j3=j3min,j3max-j0
        do i3=i3min,i3max-i0
           do i=1,nb_noneigh
              unew(ind_buffer(i),ivar)=unew(ind_buffer(i),ivar) &
                   & -flux(ind_cell(i),i3,j3,k3,ivar,idim)*oneontwotondim
           end do
        end do
        end do
        end do
     end do
     if(pressure_fix)then
     ! Update velocity divergence
     do k3=k3min,k3max-k0
     do j3=j3min,j3max-j0
     do i3=i3min,i3max-i0
        do i=1,nb_noneigh
           divu(ind_buffer(i))=divu(ind_buffer(i)) &
                & -tmp(ind_cell(i),i3,j3,k3,1,idim)*oneontwotondim
        end do
     end do
     end do
     end do
     ! Update internal energy
     do k3=k3min,k3max-k0
     do j3=j3min,j3max-j0
     do i3=i3min,i3max-i0
        do i=1,nb_noneigh
           enew(ind_buffer(i))=enew(ind_buffer(i)) &
                & -tmp(ind_cell(i),i3,j3,k3,2,idim)*oneontwotondim
        end do
     end do
     end do
     end do
     end if
     
     !-----------------------
     ! Right flux at boundary
     !-----------------------     
     ! Check if grids sits near right boundary
     ! and gather neighbor father cells index
     nb_noneigh=0
     do i=1,ncache
        if (son(nbor(ind_grid(i),2*idim))==0) then
           nb_noneigh = nb_noneigh + 1
           ind_buffer(nb_noneigh) = nbor(ind_grid(i),2*idim)
           ind_cell(nb_noneigh) = i
        end if
     end do
     ! Conservative update of new state variables
     do ivar=1,nvar
        ! Loop over boundary cells
        do k3=k3min+k0,k3max
        do j3=j3min+j0,j3max
        do i3=i3min+i0,i3max
           do i=1,nb_noneigh
              unew(ind_buffer(i),ivar)=unew(ind_buffer(i),ivar) &
                   & +flux(ind_cell(i),i3+i0,j3+j0,k3+k0,ivar,idim)*oneontwotondim
           end do
        end do
        end do
        end do
     end do
     if(pressure_fix)then
     ! Update velocity divergence
     do k3=k3min+k0,k3max
     do j3=j3min+j0,j3max
     do i3=i3min+i0,i3max
        do i=1,nb_noneigh
           divu(ind_buffer(i))=divu(ind_buffer(i)) &
                & +tmp(ind_cell(i),i3+i0,j3+j0,k3+k0,1,idim)*oneontwotondim
        end do
     end do
     end do
     end do
     ! Update internal energy
     do k3=k3min+k0,k3max
     do j3=j3min+j0,j3max
     do i3=i3min+i0,i3max
        do i=1,nb_noneigh
           enew(ind_buffer(i))=enew(ind_buffer(i)) &
                & +tmp(ind_cell(i),i3+i0,j3+j0,k3+k0,2,idim)*oneontwotondim
        end do
     end do
     end do
     end do
     end if

  end do
  ! End loop over dimensions

end subroutine godfine1
