!###########################################################
!###########################################################
!###########################################################
!###########################################################
subroutine godunov_fine(ilevel)
  use amr_commons
  use pm_commons, only: move_flag
  use hydro_commons
  implicit none
  integer::ilevel
  !--------------------------------------------------------------------------
  ! This routine is a wrapper to the second order Godunov solver.
  ! Small grids (2x2x2) are gathered from level ilevel and sent to the
  ! hydro solver. On entry, hydro variables are gathered from array uold.
  ! On exit, unew has been updated.
  !--------------------------------------------------------------------------
  integer::i,ivar,igrid,ncache,ngrid
  integer,dimension(1:nvector),save::ind_grid

  if(numbtot(1,ilevel)==0)return
  if(static)return
  if(verbose)write(*,111)ilevel

  ! Loop over active grids by vector sweeps
  ncache=active(ilevel)%ngrid
  
  if (MC_tracer) move_flag = .true.

  do igrid=1,ncache,nvector
     ngrid=MIN(nvector,ncache-igrid+1)
     do i=1,ngrid
        ind_grid(i)=active(ilevel)%igrid(igrid+i-1)
     end do
     call godfine1(ind_grid,ngrid,ilevel)
  end do

111 format('   Entering godunov_fine for level ',i2)

end subroutine godunov_fine
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
  integer::i,ivar,irad,ind,icpu,iskip
  real(dp)::d,u,v,w,e

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
     if(pressure_fix)then
        do i=1,active(ilevel)%ngrid
           divu(active(ilevel)%igrid(i)+iskip) = 0.0
        end do
        do i=1,active(ilevel)%ngrid
           d=max(uold(active(ilevel)%igrid(i)+iskip,1),smallr)
           u=0.0; v=0.0; w=0.0
           if(ndim>0)u=uold(active(ilevel)%igrid(i)+iskip,2)/d
           if(ndim>1)v=uold(active(ilevel)%igrid(i)+iskip,3)/d
           if(ndim>2)w=uold(active(ilevel)%igrid(i)+iskip,4)/d
           e=uold(active(ilevel)%igrid(i)+iskip,ndim+2)-0.5*d*(u**2+v**2+w**2)
#if NENER>0
           do irad=1,nener
              e=e-uold(active(ilevel)%igrid(i)+iskip,ndim+2+irad)
           end do
#endif
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
  !---------------------------------------------------------
  ! This routine sets array uold to its new value unew
  ! after the hydro step.
  !---------------------------------------------------------
  integer::i,ivar,irad,ind,iskip,nx_loc,ind_cell
  real(dp)::scale,d,u,v,w
  real(dp)::e_kin,e_cons,e_prim,e_trunc,div,dx,fact,d_old

  if(numbtot(1,ilevel)==0)return
  if(verbose)write(*,111)ilevel

  nx_loc=icoarse_max-icoarse_min+1
  scale=boxlen/dble(nx_loc)
  dx=0.5d0**ilevel*scale

  ! Add gravity source terms to unew
  if(poisson)then
     call add_gravity_source_terms(ilevel)
  end if

  ! Add non conservative pdV terms to unew
  ! for thermal and/or non-thermal energies
  if(pressure_fix.OR.nener>0)then
     call add_pdv_source_terms(ilevel)
  endif

  ! Set uold to unew for myid cells
  do ind=1,twotondim
     iskip=ncoarse+(ind-1)*ngridmax
     do ivar=1,nvar
        do i=1,active(ilevel)%ngrid
           uold(active(ilevel)%igrid(i)+iskip,ivar) = unew(active(ilevel)%igrid(i)+iskip,ivar)
        end do
     end do
     if(pressure_fix)then
        ! Correct total energy if internal energy is too small
        do i=1,active(ilevel)%ngrid
           ind_cell=active(ilevel)%igrid(i)+iskip
           d=max(uold(ind_cell,1),smallr)
           u=0.0; v=0.0; w=0.0
           if(ndim>0)u=uold(ind_cell,2)/d
           if(ndim>1)v=uold(ind_cell,3)/d
           if(ndim>2)w=uold(ind_cell,4)/d
           e_kin=0.5*d*(u**2+v**2+w**2)
#if NENER>0
           do irad=1,nener
              e_kin=e_kin+uold(ind_cell,ndim+2+irad)
           end do
#endif
           e_cons=uold(ind_cell,ndim+2)-e_kin
           e_prim=enew(ind_cell)
           ! Note: here divu=-div.u*dt
           div=abs(divu(ind_cell))*dx/dtnew(ilevel)
           e_trunc=beta_fix*d*max(div,3.0*hexp*dx)**2
           if(e_cons<e_trunc)then
              uold(ind_cell,ndim+2)=e_prim+e_kin
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
subroutine add_gravity_source_terms(ilevel)
  use amr_commons
  use hydro_commons
  use poisson_commons
  implicit none
  integer::ilevel
  !--------------------------------------------------------------------------
  ! This routine adds to unew the gravity source terms
  ! with only half a time step. Only the momentum and the
  ! total energy are modified in array unew.
  !--------------------------------------------------------------------------
  integer::i,ivar,ind,iskip,nx_loc,ind_cell
  real(dp)::d,u,v,w,e_kin,e_prim,d_old,fact

  if(numbtot(1,ilevel)==0)return
  if(verbose)write(*,111)ilevel

  ! Add gravity source term at time t with half time step
  do ind=1,twotondim
     iskip=ncoarse+(ind-1)*ngridmax
     do i=1,active(ilevel)%ngrid
        ind_cell=active(ilevel)%igrid(i)+iskip
        d=max(unew(ind_cell,1),smallr)
        u=0.0; v=0.0; w=0.0
        if(ndim>0)u=unew(ind_cell,2)/d
        if(ndim>1)v=unew(ind_cell,3)/d
        if(ndim>2)w=unew(ind_cell,4)/d
        e_kin=0.5*d*(u**2+v**2+w**2)
        e_prim=unew(ind_cell,ndim+2)-e_kin
        d_old=max(uold(ind_cell,1),smallr)
        fact=d_old/d*0.5*dtnew(ilevel)
        if(ndim>0)then
           u=u+f(ind_cell,1)*fact
           unew(ind_cell,2)=d*u
        endif
        if(ndim>1)then
           v=v+f(ind_cell,2)*fact
           unew(ind_cell,3)=d*v
        end if
        if(ndim>2)then
           w=w+f(ind_cell,3)*fact
           unew(ind_cell,4)=d*w
        endif
        e_kin=0.5*d*(u**2+v**2+w**2)
        unew(ind_cell,ndim+2)=e_prim+e_kin
     end do
  end do

111 format('   Entering add_gravity_source_terms for level ',i2)

end subroutine add_gravity_source_terms
!###########################################################
!###########################################################
!###########################################################
!###########################################################
subroutine add_pdv_source_terms(ilevel)
  use amr_commons
  use hydro_commons
  implicit none
  integer::ilevel
  !---------------------------------------------------------
  ! This routine adds the pdV source term to the internal
  ! energy equation and to the non-thermal energy equations.
  !---------------------------------------------------------
  integer::i,ivar,irad,ind,iskip,nx_loc,ind_cell1
  integer::ncache,igrid,ngrid,idim,id1,ig1,ih1,id2,ig2,ih2
  integer,dimension(1:3,1:2,1:8)::iii,jjj
  real(dp)::scale,dx,dx_loc,d,u,v,w,eold

  integer ,dimension(1:nvector),save::ind_grid,ind_cell
  integer ,dimension(1:nvector,0:twondim),save::igridn
  integer ,dimension(1:nvector,1:ndim),save::ind_left,ind_right
  real(dp),dimension(1:nvector,1:ndim,1:ndim),save::velg,veld
  real(dp),dimension(1:nvector,1:ndim),save::dx_g,dx_d
  real(dp),dimension(1:nvector),save::divu_loc

  if(numbtot(1,ilevel)==0)return
  if(verbose)write(*,111)ilevel

  nx_loc=icoarse_max-icoarse_min+1
  scale=boxlen/dble(nx_loc)
  dx=0.5d0**ilevel
  dx_loc=dx*scale

  iii(1,1,1:8)=(/1,0,1,0,1,0,1,0/); jjj(1,1,1:8)=(/2,1,4,3,6,5,8,7/)
  iii(1,2,1:8)=(/0,2,0,2,0,2,0,2/); jjj(1,2,1:8)=(/2,1,4,3,6,5,8,7/)
  iii(2,1,1:8)=(/3,3,0,0,3,3,0,0/); jjj(2,1,1:8)=(/3,4,1,2,7,8,5,6/)
  iii(2,2,1:8)=(/0,0,4,4,0,0,4,4/); jjj(2,2,1:8)=(/3,4,1,2,7,8,5,6/)
  iii(3,1,1:8)=(/5,5,5,5,0,0,0,0/); jjj(3,1,1:8)=(/5,6,7,8,1,2,3,4/)
  iii(3,2,1:8)=(/0,0,0,0,6,6,6,6/); jjj(3,2,1:8)=(/5,6,7,8,1,2,3,4/)

  ! Loop over myid grids by vector sweeps
  ncache=active(ilevel)%ngrid
  do igrid=1,ncache,nvector

     ! Gather nvector grids
     ngrid=MIN(nvector,ncache-igrid+1)
     do i=1,ngrid
        ind_grid(i)=active(ilevel)%igrid(igrid+i-1)
     end do

     ! Gather neighboring grids
     do i=1,ngrid
        igridn(i,0)=ind_grid(i)
     end do
     do idim=1,ndim
        do i=1,ngrid
           ind_left (i,idim)=nbor(ind_grid(i),2*idim-1)
           ind_right(i,idim)=nbor(ind_grid(i),2*idim  )
           igridn(i,2*idim-1)=son(ind_left (i,idim))
           igridn(i,2*idim  )=son(ind_right(i,idim))
        end do
     end do

     ! Loop over cells
     do ind=1,twotondim

        ! Compute central cell index
        iskip=ncoarse+(ind-1)*ngridmax
        do i=1,ngrid
           ind_cell(i)=iskip+ind_grid(i)
        end do

        ! Gather all neighboring velocities
        do idim=1,ndim
           id1=jjj(idim,1,ind); ig1=iii(idim,1,ind)
           ih1=ncoarse+(id1-1)*ngridmax
           do i=1,ngrid
              if(igridn(i,ig1)>0)then
                 velg(i,idim,1:ndim) = uold(igridn(i,ig1)+ih1,2:ndim+1)/max(uold(igridn(i,ig1)+ih1,1),smallr)
                 dx_g(i,idim) = dx_loc
              else
                 velg(i,idim,1:ndim) = uold(ind_left(i,idim),2:ndim+1)/max(uold(ind_left(i,idim),1),smallr)
                 dx_g(i,idim) = dx_loc*1.5_dp
              end if
           enddo
           id2=jjj(idim,2,ind); ig2=iii(idim,2,ind)
           ih2=ncoarse+(id2-1)*ngridmax
           do i=1,ngrid
              if(igridn(i,ig2)>0)then
                 veld(i,idim,1:ndim)= uold(igridn(i,ig2)+ih2,2:ndim+1)/max(uold(igridn(i,ig2)+ih2,1),smallr)
                 dx_d(i,idim)=dx_loc
              else
                 veld(i,idim,1:ndim)= uold(ind_right(i,idim),2:ndim+1)/max(uold(ind_right(i,idim),1),smallr)
                 dx_d(i,idim)=dx_loc*1.5_dp
              end if
           enddo
        end do
        ! End loop over dimensions

        ! Compute divu = Trace G
        divu_loc(1:ngrid)=0.0d0
        do i=1,ngrid
           do idim=1,ndim
              divu_loc(i) = divu_loc(i) + (veld(i,idim,idim)-velg(i,idim,idim)) &
                   &                    / (dx_g(i,idim)     +dx_d(i,idim))
           enddo
        end do

        ! Update thermal internal energy
        if(pressure_fix)then
           do i=1,ngrid
              ! Compute old thermal energy
              d=max(uold(ind_cell(i),1),smallr)
              u=0.0; v=0.0; w=0.0
              if(ndim>0)u=uold(ind_cell(i),2)/d
              if(ndim>1)v=uold(ind_cell(i),3)/d
              if(ndim>2)w=uold(ind_cell(i),4)/d
              eold=uold(ind_cell(i),ndim+2)-0.5*d*(u**2+v**2+w**2)
#if NENER>0
              do irad=1,nener
                 eold=eold-uold(ind_cell(i),ndim+2+irad)
              end do
#endif
              ! Add -pdV term
              enew(ind_cell(i))=enew(ind_cell(i)) &
                   & -(gamma-1.0d0)*eold*divu_loc(i)*dtnew(ilevel)
           end do
        end if

#if NENER>0
        do irad=1,nener
           do i=1,ngrid
              ! Add -pdV term
              unew(ind_cell(i),ndim+2+irad)=unew(ind_cell(i),ndim+2+irad) &
                & -(gamma_rad(irad)-1.0d0)*uold(ind_cell(i),ndim+2+irad)*divu_loc(i)*dtnew(ilevel)
           end do
        end do
#endif

     enddo
     ! End loop over cells
  end do
  ! End loop over grids

  return

  ! This is the old technique based on the "pressure fix" option.

  ! Update thermal internal energy
  if(pressure_fix)then
     do ind=1,twotondim
        iskip=ncoarse+(ind-1)*ngridmax
        do i=1,active(ilevel)%ngrid
           ind_cell1=active(ilevel)%igrid(i)+iskip
           ! Compute old thermal energy
           d=max(uold(ind_cell1,1),smallr)
           u=0.0; v=0.0; w=0.0
           if(ndim>0)u=uold(ind_cell1,2)/d
           if(ndim>1)v=uold(ind_cell1,3)/d
           if(ndim>2)w=uold(ind_cell1,4)/d
           eold=uold(ind_cell1,ndim+2)-0.5*d*(u**2+v**2+w**2)
#if NENER>0
           do irad=1,nener
              eold=eold-uold(ind_cell1,ndim+2+irad)
           end do
#endif
           ! Add pdV term
           enew(ind_cell1)=enew(ind_cell1) &
                & +(gamma-1.0d0)*eold*divu(ind_cell1) ! Note: here divu=-div.u*dt
        end do
     end do
  end if

#if NENER>0
  do irad=1,nener
     do ind=1,twotondim
        iskip=ncoarse+(ind-1)*ngridmax
        do i=1,active(ilevel)%ngrid
           ind_cell1=active(ilevel)%igrid(i)+iskip
           unew(ind_cell1,ndim+2+irad)=unew(ind_cell1,ndim+2+irad) &
                & +(gamma_rad(irad)-1.0d0)*uold(ind_cell1,ndim+2+irad)*divu(ind_cell1) ! Note: here divu=-div.u*dt
        end do
     end do
  end do
#endif

111 format('   Entering add_pdv_source_terms for level ',i2)

end subroutine add_pdv_source_terms
!###########################################################
!###########################################################
!###########################################################
!###########################################################
subroutine godfine1(ind_grid, ncache, ilevel)
  use amr_commons
  use hydro_commons
  use poisson_commons
  implicit none
  integer::ilevel,ncache
  integer,dimension(1:nvector)::ind_grid
  !-------------------------------------------------------------------
  ! This routine gathers first hydro variables from neighboring grids
  ! to set initial conditions in a 6x6x6 grid. It interpolates from
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

  real(dp),dimension(1:nvector,1:ndim), save :: xnew

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

  !--------------------------------------
  ! Move tracer particles along with the flux
  !--------------------------------------
  if (MC_tracer) then
     call move_tracers_oct(ind_grid, flux, ilevel)
  end if

end subroutine godfine1

subroutine move_tracers_oct(ind_grid, fluxes, ilevel)
  use amr_parameters      ! nx, ny, nz, dp, ngridmax, nvector, …
  use amr_commons, only   : ncoarse, father, xg, son
  use pm_commons, only    : xp, headp, mp, localseed, numbp, nextp, move_flag
  use random, only        : ranf
  use hydro_commons, only : uold, if1, if2, jf1, jf2, kf1, kf2, nvar

  implicit none

  integer,dimension(1:nvector), intent(in)   :: ind_grid
  real(dp),dimension(1:nvector, if1:if2, jf1:jf2, kf1:kf2, 1:nvar, 1:ndim),intent(in)::fluxes
  integer, intent(in) :: ilevel

  !-------------------------------------------------------------------
  ! Implement a Monte Carlo sampling of the gas properties following
  ! the fluxes of mass from oct to oct.
  !-------------------------------------------------------------------
  integer,dimension(1:nvector,0:twondim) :: ind_ngrid
  real(dp) :: flux, Fout, mass, rand
  integer,dimension(1:nvector, 1:twotondim) :: ind_cell
  integer,dimension(1:nvector, 1:twotondim, 0:twondim) :: ind_ncell
  integer,dimension(1:nvector, 0:twondim) :: tmp_ncell

  integer :: i, j, k, dir, dim, ison, iskip, icell, igrid_cell, ficell, ncell, ipart, new_icell, ix, iy, iz
  integer :: ixnc, iync, iznc
  integer :: dim0, nxny, dirm2, nx_loc
  real(kind=dp) :: scale, dx
  real(kind=dp), dimension(1:3) :: x, xbound, skip_loc

  ! integer, save :: ncall = 0

  ! ncall = ncall + 1
  ! write(*, '(a,i3,a)') '===', ncall, "'th call of move_tracers_oct"
  nxny = nx*ny

  scale = boxlen/dble(nx_loc)
  dx = 0.5D0**ilevel
  xbound(1:3)=(/dble(nx),dble(ny),dble(nz)/)
  nx_loc=(icoarse_max-icoarse_min+1)
  skip_loc=(/0.0d0, 0.0d0, 0.0d0/)
  if(ndim>0) skip_loc(1) = dble(icoarse_min)
  if(ndim>1) skip_loc(2) = dble(jcoarse_min)
  if(ndim>2) skip_loc(3) = dble(kcoarse_min)
  scale = boxlen/dble(nx_loc)

  ! Iterate over neighbour of father grid
  call getnborgrids(ind_grid, ind_ngrid, nvector)

  ! Precompute the indexes of the cells of each grid
  do j = 1, nvector
     do i = 1, twotondim
        iskip = ncoarse + (i - 1)*ngridmax
        ind_cell(j, i) = ind_grid(j) + iskip
     end do
  end do

  ! Get each cell's neighbour in all 6 directions
  do i = 1, twotondim
     call getnborfather(ind_cell(:, i), tmp_ncell, nvector, ilevel)
     do j = 0, twondim
        ind_ncell(:, i, j) = tmp_ncell(:, j)
     end do
  end do


  ! do j = 1, nvector
  !    write(*, '(i4, 2x, 2(f8.5, 2x), i4)') ind_grid(j), xg(ind_grid(j), :), numbp(ind_grid(j))
  ! end do

  ! do j = 1, nvector
  !    print*, 'Grid j  ', j, ind_grid(j)
  !    print*, 'position', xg(ind_grid(j), :)
  !    ipart = headp(ind_grid(j))
  !    do i = 1, numbp(ind_grid(j))
  !       print*, ipart, xp(ipart, :)
  !       ipart = nextp(ipart)
  !    end do
  ! end do

  do j = 1, nvector
     ! Loop over all particles
     ipart = headp(ind_grid(j))
     ! print*, '==================== new grid', ind_grid(j)

     do i = 1, numbp(ind_grid(j))
        ! print*, "   >> Particle", ipart, xp(ipart, :)
        ! Skip already moved particles
        ! .not. tracer_moved(ipart)

        ! print*, 'part  ', ipart, ind_grid(j), move_flag(ipart)

        if (mp(ipart) == 0d0 .and. move_flag(ipart)) then

           ! Find cell in which the particle is
           ! see amr/refine_utils.f90:202
           ix = 1; iy = 1; iz = 1
           do dim = 1, ndim
              x(dim) = (xp(ipart, dim) / scale + skip_loc(dim) - xg(ind_grid(j), dim))/dx + 1.5d0
              ! print*, 'x(dim)', x(dim), ind_grid(j)
           end do

           ix = x(1)
#IF NDIM > 1
           iy = x(2)
#ENDIF
#IF NDIM > 2
           iz = x(3)
#ENDIF
           ison = 1 + (ix-1) + nx*(iy-1) + nxny*(iz-1)
           iskip = ncoarse + (ison-1)*ngridmax
           icell = iskip + ind_grid(j)

           ! print*, 'computing flux', ipart

           ! Compute the outflux (<0)
           Fout = 0
           do dir = 1, twondim
              call getFlux(dir, ix, iy, iz, j, fluxes, flux)
              if (flux < 0) Fout = Fout + flux
           end do

           mass = uold(ind_grid(j), 1) ! mass of cell

           call ranf(localseed, rand)

           ! Move the particle
           if (rand < -Fout/mass) then
              ! Pick a direction
              call ranf(localseed, rand)

              ! Two cases:
              ! 1. stay in the same grid
              ! 2. move to a neighbor grid
              do dir = 1, twondim
                 call getFlux(dir, ix, iy, iz, j, fluxes, flux)
                 if (rand < flux/Fout) then ! Move particle
                    ! print*, 'in direction', dir, 'from', ix, iy, iz

                    dirm2 = (dir - 1) / 2 + 1 ! 1,2->1 | 3,4->2 | 5,6->3

                    ! Two cases:
                    ! 1. stay in the same grid
                    ! 2. move to a neighbor grid

                    ! write(*, '(a3, *(2x, a6))') 'k', ''
                    ! do k = 1, twotondim
                    !    write(*, '(i3,*(2x, i6))') k, ind_ncell(j, k, :)
                    ! end do

                    ! print*, 'before', ipart, xp(ipart, :), move_flag(ipart)
                    do dim = 1, ndim
                       if (dirm2 == dim) then
                          if (mod(dir, 2) == 1) then ! going left
                             xp(ipart, dim) = xp(ipart, dim) - dx
                          else                       ! going right
                             xp(ipart, dim) = xp(ipart, dim) + dx
                          end if
                       end if
                    end do
                    ! print*, 'after ', ipart, xp(ipart, :), move_flag(ipart)
                    ! print*, ''

                    exit
                 else                     ! Increase proba for moving in next direction
                    if (flux < 0) rand = rand - flux / Fout
                 end if
               end do
            end if
        end if

        ! Next one
        ! print*, 'next part'
        move_flag(ipart) = .false.
        ipart = nextp(ipart)
     end do
  end do

contains
  function goingToOtherGrid(ix, iy, iz, dir)
    logical :: goingToOtherGrid

    integer, intent(in) :: ix, iy, iz, dir
    goingToOtherGrid = &
         (ix == 1 .and. dir == 1) .or. &
         (ix == 3 .and. dir == 2) .or. &
         (iy == 1 .and. dir == 3) .or. &
         (iy == 3 .and. dir == 4) .or. &
         (iz == 1 .and. dir == 5) .or. &
         (iz == 3 .and. dir == 6)

  end function goingToOtherGrid

  ! function getNeighbour(oct, dir) result (noct)
  !   integer, dimension(1:nvector), intent(in) :: oct
  !   integer, intent(in) :: dir

  !   ! Output
  !   integer, dimension(1:nvector,1:twotondim) :: noct

  !   ! TODO
  !   noct = 0

  ! end function getNeighbour

  subroutine getFlux(dir, ii0, jj0, kk0, j, fluxes, flux)
    integer, intent(in)  :: dir, j
    integer, intent(in) :: ii0, jj0, kk0
    real(dp), intent(in) :: fluxes(:,:,:,:,:,:)

    real(dp), intent(out) :: flux

    integer :: sign ! this is the sign to get fluxes from cell out of it
    integer :: dim, nxny, ii, jj, kk

    ii = ii0
    jj = jj0
    kk = kk0
    ! the sign is +1 when the direction is 1, 3, 5
    ! the sign is -1 when the direction is 2, 4, 6
    sign = 1
    if (mod(dir, 2) == 0) sign = -1
    dim = dir / 3 + 1 ! so that 1,2 -> 1 & 3,4 -> 2 & 4,5 -> 3

    ! Select the location given ii, jj, kk and the direction
    if (dim == 1)      then
       if (sign == -1) ii = ii + 1
    else if (dim == 2) then
       if (sign == -1) jj = jj + 1
       kk = 1
    else
       if (sign == -1) kk = kk + 1
    end if

    flux = sign*fluxes(j, ii, jj, kk, 1, dim)
  end subroutine getFlux

  ! function getCellsInDir(oct, dir) result(icells)
  !   integer, intent(in) :: oct, dir
  !   integer, dimension(1:2*(ndim-1)) :: icells

  !   integer, dimension(1:2*(ndim-1)) :: iskip
  !   integer, dimension(1:4,1:6), save :: ccc

  !   ccc(1:4,1) = (/1, 3, 5, 7/)
  !   ccc(1:4,2) = (/2, 4, 6, 8/)
  !   ccc(1:4,3) = (/1, 2, 5, 6/)
  !   ccc(1:4,4) = (/3, 4, 7, 8/)
  !   ccc(1:4,5) = (/1, 2, 3, 4/)
  !   ccc(1:4,6) = (/5, 6, 7, 8/)

  !   ! TODO : compute the absolute location of cell, not relative
  !   iskip = ncoarse + (ccc(:, dir) - 1)*ngridmax
  !   icells(:) = oct + iskip(:)

  ! end function getCellsInDir

end subroutine move_tracers_oct
