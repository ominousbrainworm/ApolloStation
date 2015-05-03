#define DAMAGE			1
#define FIRE			2

/obj/spacepod
	name = "\improper space pod"
	desc = "A space pod meant for space travel. This one looks rather bare."
	icon = 'icons/48x48/pods.dmi'
	density = 1 //Dense. To raise the heat.
	opacity = 0
	anchored = 1
	unacidable = 1
	layer = 3.9
	infra_luminosity = 15
	var/list/occupants = list("pilot" = null, "passenger" = null)
	var/datum/spacepod/equipment/equipment_system
	var/datum/gas_mixture/cabin_air
	var/obj/machinery/portable_atmospherics/canister/internal_tank
	var/datum/effect/effect/system/ion_trail_follow/space_trail/ion_trail
	var/use_internal_tank = 0
	var/datum/global_iterator/pr_int_temp_processor //normalizes internal air mixture temperature
	var/datum/global_iterator/pr_give_air //moves air from tank to cabin
	var/inertia_dir = 0
	var/hatch_open = 0
	var/next_firetime = 0
	var/list/pod_overlays
	var/health = 100 // pods without armor are tough as a spongecake
	var/lights = 0
	var/lights_power = 6
	var/allow2enter = 1
	var/empcounter = 0 //Used for disabling movement when hit by an EMP
	var/ticks_per_move = 3
	var/move_tick = 0
	var/battery_type = "/obj/item/weapon/cell/super"
	var/fire_threshold_health = 0.2 // threshold heat for fires to start

/obj/spacepod/New()
	. = ..()
	dir = EAST
	bound_width = 64
	bound_height = 64
	equipment_system = new(src)
	equipment_system.equip( new /obj/item/device/spacepod_equipment/misc/autopilot )
	add_cabin()
	add_airtank()
	src.ion_trail = new /datum/effect/effect/system/ion_trail_follow/space_trail()
	src.ion_trail.set_up(src)
	src.ion_trail.start()
	src.use_internal_tank = 1
	pr_int_temp_processor = new /datum/global_iterator/pod_preserve_temp(list(src))
	pr_give_air = new /datum/global_iterator/pod_tank_give_air(list(src))

	spacepods_list += src

	update_icons()

/obj/spacepod/Del()
	spacepods_list -= src
	..()

/obj/spacepod/process()
	if(src.empcounter > 0)
		src.empcounter--
	else
		processing_objects.Remove(src)

/obj/spacepod/proc/update_icons()
	if( istype( equipment_system.armor, /obj/item/pod_parts/armor/command ))
		icon_state = "pod_com"
	else if( istype( equipment_system.armor, /obj/item/pod_parts/armor/security ))
		icon_state = "pod_sec"
	else
		icon_state = "pod"

	if(!pod_overlays)
		pod_overlays = new/list(2)
		pod_overlays[DAMAGE] = image(icon, icon_state="pod_damage")
		pod_overlays[FIRE] = image(icon, icon_state="pod_fire")

	overlays.Cut()

	if(health <= round(initial(health)/2))
		overlays += pod_overlays[DAMAGE]
	if( is_on_fire() )
		overlays += pod_overlays[FIRE]

/obj/spacepod/proc/is_on_fire()
	if( equipment_system )
		if( equipment_system.engine_system )
			return equipment_system.engine_system.fire
	return 0

/obj/spacepod/proc/fire_hazard()
	return health/initial(health) <= fire_threshold_health

/obj/spacepod/bullet_act(var/obj/item/projectile/P)
	if(P.damage && !P.nodamage)
		deal_damage(P.damage)
	else if(P.flag == "energy" && istype(P,/obj/item/projectile/ion)) //needed to make sure ions work properly
		empulse(src, 1, 1)

/obj/spacepod/blob_act()
	deal_damage(30)
	return

/obj/spacepod/proc/deal_damage(var/damage)
	var/oldhealth = health
	health = max(0, health - damage)
	var/percentage = (health / initial(health)) * 100
	if(occupants["pilot"] && oldhealth > health && percentage <= 25 && percentage > 0)
		var/sound/S = sound('sound/effects/engine_alert2.ogg')
		S.wait = 0 //No queue
		S.channel = 0 //Any channel
		S.volume = 50
		occupants["pilot"] << S
		if(occupants["passenger"])
			occupants["passenger"] << S
	if(occupants["pilot"] && oldhealth > health && !health)
		var/sound/S = sound('sound/effects/engine_alert1.ogg')
		S.wait = 0
		S.channel = 0
		S.volume = 50
		occupants["pilot"] << S
		if(occupants["passenger"])
			occupants["passenger"] << S
	if(!health)
		explode()

	update_icons()

/obj/spacepod/proc/explode()
	spawn(0)
		if(occupants["pilot"])
			if(occupants["passenger"])
				occupants["passenger"] << "<big><span class='warning'>Critical damage to the vessel detected, core explosion imminent!</span></big>"
			occupants["pilot"] << "<big><span class='warning'>Critical damage to the vessel detected, core explosion imminent!</span></big>"
			for(var/i = 10, i >= 0; --i)
				if(occupants["pilot"])
					occupants["pilot"] << "<span class='warning'>[i]</span>"
				if(occupants["passenger"])
					occupants["passenger"] << "<span class='warning'>[i]</span>"
				if(i == 0)
					explosion(loc, 2, 4, 8)
					del(src)
				sleep(10)

/obj/spacepod/proc/repair_damage(var/repair_amount)
	if(health)
		health = min(initial(health), health + repair_amount)
		update_icons()


/obj/spacepod/ex_act(severity)
	switch(severity)
		if(1)
			var/mob/living/carbon/human/H = occupants["pilot"]
			var/mob/living/carbon/human/H2 = occupants["passenger"]
			if(H)
				H.loc = get_turf(src)
				H.ex_act(severity + 1)
				H << "<span class='warning'>You are forcefully thrown from \the [src]!</span>"
			if(H2)
				H2.loc = get_turf(src)
				H2.ex_act(severity + 1)
				H2 << "<span class='warning'>You are forcefully thrown from \the [src]!</span>"
			del(ion_trail)
			del(src)
		if(2)
			deal_damage(100)
		if(3)
			if(prob(40))
				deal_damage(50)

/obj/spacepod/emp_act(severity)
	var/obj/item/weapon/cell/battery = equipment_system.battery

	switch(severity)
		if(1)
			if(src.occupants["pilot"])
				src.occupants["pilot"] << "<span class='warning'>The pod console flashes 'Heavy EMP WAVE DETECTED'.</span>" //warn the occupants
			if(src.occupants["passenger"])
				src.occupants["passenger"] << "<span class='warning'>The pod console flashes 'EMP WAVE DETECTED'.</span>" //warn the occupants


			if(battery)
				battery.charge = max(0, battery.charge - 5000) //Cell EMP act is too weak, this pod needs to be sapped.
			src.deal_damage(100)
			if(src.empcounter < 40)
				src.empcounter = 40 //Disable movement for 40 ticks. Plenty long enough.
			processing_objects.Add(src)

		if(2)
			if(src.occupants["pilot"])
				src.occupants["pilot"] << "<span class='warning'>The pod console flashes 'EMP WAVE DETECTED'.</span>" //warn the occupants
			if(src.occupants["passenger"])
				src.occupants["passenger"] << "<span class='warning'>The pod console flashes 'EMP WAVE DETECTED'.</span>" //warn the occupants

			src.deal_damage(40)
			if(battery)
				battery.charge = max(0, battery.charge - 2500) //Cell EMP act is too weak, this pod needs to be sapped.
			if(src.empcounter < 20)
				src.empcounter = 20 //Disable movement for 20 ticks.
			processing_objects.Add(src)

/obj/spacepod/attackby(obj/item/W as obj, mob/user as mob, params)
	if( istype( W, /obj/item/weapon/tank ))
		if( equipment_system.fill_engine( W ))
			usr << "You hook the phoron tank up to the fuel hose and with a hiss all of the fuel is added to the pod's fuel tank."
	if(iscrowbar(W))
		hatch_open = !hatch_open
		playsound(loc, 'sound/items/Crowbar.ogg', 50, 1)
		user << "<span class='notice'>You [hatch_open ? "open" : "close"] the maintenance hatch.</span>"
	if(istype(W, /obj/item/weapon/cell))
		if(!hatch_open)
			user << "\red The maintenance hatch is closed!"
			return
		if(equipment_system.battery)
			user << "<span class='notice'>The pod already has a battery.</span>"
			return

		equipment_system.equip(W, user)
		return
	if(istype(W, /obj/item/device/spacepod_equipment))
		if(!hatch_open)
			user << "\red The maintenance hatch is closed!"
			return

		// Adding the equipment to the system
		equipment_system.equip(W, user)
	if(istype(W, /obj/item/pod_parts/armor))
		if(!hatch_open)
			user << "\red The maintenance hatch is closed!"
			return
		if(equipment_system.armor)
			user << "<span class='notice'>The pod already has armor.</span>"
			return

		equipment_system.equip(W, user)
		return

	if(istype(W, /obj/item/weapon/weldingtool))
		if(!hatch_open)
			user << "\red You must open the maintenance hatch before attempting repairs."
			return
		var/obj/item/weapon/weldingtool/WT = W
		if(!WT.isOn())
			user << "\red The welder must be on for this task."
			return
		if (health < initial(health))
			user << "\blue You start welding the spacepod..."
			playsound(loc, 'sound/items/Welder.ogg', 50, 1)
			if(do_after(user, 20))
				if(!src || !WT.remove_fuel(3, user)) return
				repair_damage(10)
				user << "\blue You mend some [pick("dents","bumps","damage")] with \the [WT]"
		else
			user << "\blue <b>\The [src] is fully repaired!</b>"

/obj/spacepod/attack_hand(mob/user as mob)
	if(!hatch_open)
		return ..()
	if(!equipment_system || !istype(equipment_system))
		user << "<span class='warning'>The pod has no equpment datum, or is the wrong type, yell at pomf.</span>"
		return

	// Removing the equipment
	var/obj/item/SPE = input(user, "Remove which equipment?", null, null) as null|anything in equipment_system.spacepod_equipment
	if( SPE )
		equipment_system.dequip( SPE, user )

	return

/obj/spacepod/verb/toggle_internal_tank()
	if(usr == src.occupants["pilot"])
		set name = "Toggle internal airtank usage"
		set category = "Spacepod"
		set src = usr.loc
		set popup_menu = 0

		use_internal_tank = !use_internal_tank
		occupants_announce( "Now taking air from [use_internal_tank?"internal airtank":"environment"]." )
		return

/obj/spacepod/proc/add_cabin()
	cabin_air = new
	cabin_air.temperature = T20C
	cabin_air.volume = 200
	cabin_air.gas["oxygen"] = O2STANDARD*cabin_air.volume/(R_IDEAL_GAS_EQUATION*cabin_air.temperature)
	cabin_air.gas["nitrogen"] = N2STANDARD*cabin_air.volume/(R_IDEAL_GAS_EQUATION*cabin_air.temperature)
	return cabin_air

/obj/spacepod/proc/add_airtank()
	internal_tank = new /obj/machinery/portable_atmospherics/canister/air(src)
	return internal_tank

/obj/spacepod/proc/get_turf_air()
	var/turf/T = get_turf(src)
	if(T)
		. = T.return_air()
	return

/obj/spacepod/remove_air(amount)
	if(use_internal_tank)
		return cabin_air.remove(amount)
	else
		var/turf/T = get_turf(src)
		if(T)
			return T.remove_air(amount)
	return

/obj/spacepod/return_air()
	if(use_internal_tank)
		return cabin_air
	return get_turf_air()

/obj/spacepod/proc/return_pressure()
	. = 0
	if(use_internal_tank)
		. =  cabin_air.return_pressure()
	else
		var/datum/gas_mixture/t_air = get_turf_air()
		if(t_air)
			. = t_air.return_pressure()
	return

/obj/spacepod/proc/return_temperature()
	. = 0
	if(use_internal_tank)
		. = cabin_air.temperature
	else
		var/datum/gas_mixture/t_air = get_turf_air()
		if(t_air)
			. = t_air.temperature
	return

/obj/spacepod/proc/moved_inside(var/mob/living/carbon/human/H as mob)
	var/fukkendisk
	for( var/obj/A in usr.contents )
		if( istype( A, /obj/item/weapon/disk/nuclear ))
			fukkendisk = A

	if(fukkendisk)
		usr << "\red <B>The nuke-disk locks the door as you try to get in. You evil person.</b>"
		return

	if(H && H.client && H in range(1))
		if(src.occupants["pilot"] && src.occupants["passenger"])
			H << "<span class='notice'>[src.name] is full.</span>"
			return

		if(src.occupants["pilot"] && !src.occupants["passenger"])
			var/mob/pilot = src.occupants["pilot"]
			if(pilot.ckey == H.ckey)
				H.visible_message("You climb over the console and drop down into the secondary seat.")
				H.reset_view(src)
				/*
				H.client.perspective = EYE_PERSPECTIVE
				H.client.eye = src
				*/
				H.stop_pulling()
				H.forceMove(src)
				src.occupants["pilot"] = null
				src.occupants["passenger"] = H
				src.add_fingerprint(H)
				src.forceMove(src.loc)
				//dir = dir_in
				playsound(src, 'sound/machines/windowdoor.ogg', 50, 1)
				return 1
			else
				H.reset_view(src)
				/*
				H.client.perspective = EYE_PERSPECTIVE
				H.client.eye = src
				*/
				H.stop_pulling()
				H.forceMove(src)
				src.occupants["passenger"] = H
				src.add_fingerprint(H)
				src.forceMove(src.loc)
				//dir = dir_in
				playsound(src, 'sound/machines/windowdoor.ogg', 50, 1)
				return 1

		else
			if(!src.occupants["pilot"])
				H.reset_view(src)
				/*
				H.client.perspective = EYE_PERSPECTIVE
				H.client.eye = src
				*/
				H.stop_pulling()
				H.forceMove(src)
				src.occupants["pilot"] = H
				src.add_fingerprint(H)
				src.forceMove(src.loc)
				//dir = dir_in
				playsound(src, 'sound/machines/windowdoor.ogg', 50, 1)
				return 1
			else
				return
	else
		return 0

/obj/spacepod/proc/moved_other_inside(var/mob/living/carbon/human/H as mob)
	if(!src.occupants["passenger"])
		H.reset_view(src)
		H.stop_pulling()
		H.forceMove(src)
		src.occupants["passenger"] = H
		src.forceMove(src.loc)
		playsound(src, 'sound/machines/windowdoor.ogg', 50, 1)
		return 1
	else
		return

/obj/spacepod/proc/occupants_announce( var/message, var/type = 1, var/big = 0 )
	var/full_message = ""

	if( big )
		full_message += "<big>"

	if( type == 1 )
		full_message += "<span class='notice'>"
	else if( type == 2 )
		full_message += "<span class='warning'>"

	if( message )
		full_message += message

	if( type > 0 ) // if we had a header, better close it
		full_message += "</span>"

	if( big )
		full_message += "/<big>"

	for( var/chair in occupants )
		var/mob/occupant = occupants[chair]
		if( occupant )
			occupant << full_message


/obj/spacepod/MouseDrop_T(mob/M as mob, mob/user as mob)
	if(!isliving(M)) return
	if(M != user)
		if(M.stat != 0)
			if(allow2enter)
				if(!src.occupants["passenger"])
					visible_message("\red [user.name] starts loading [M.name] into the pod!")
					sleep(10)
					moved_other_inside(M)
				else if(src.occupants["passenger"] && !src.occupants["pilot"])
					usr << "\red <b>You can't put a corpse into the driver's seat!</b>"
					return
		else
			return
	else
		move_inside(M, user)


/obj/spacepod/verb/move_inside()
	set category = "Object"
	set name = "Enter Pod"
	set src in oview(1)

	var/fukkendisk
	for( var/obj/A in usr.contents )
		if( istype( A, /obj/item/weapon/disk/nuclear ))
			fukkendisk = A

	if(usr.restrained() || usr.stat || usr.weakened || usr.stunned || usr.paralysis || usr.resting) //are you cuffed, dying, lying, stunned or other
		return

	if (usr.stat || !ishuman(usr))
		return

	if(fukkendisk)
		usr << "\red <B>The nuke-disk is locking the door every time you try to open it. You get the feeling that it doesn't want to go into the spacepod.</b>"
		return

	for(var/mob/living/carbon/slime/M in range(1,usr))
		if(M.Victim == usr)
			usr << "You're too busy getting your life sucked out of you."
			return

	if(src.occupants["pilot"])
		if(allow2enter)
			if(!src.occupants["passenger"])
				usr << "\blue <B>You start climbing into the passenger's seat.</B>"
				if(enter_after(20,usr))
					moved_inside(usr)
					src.occupants["pilot"] = null
				else
					usr << "You stop entering the spacepod."
				return
			else
				usr << "\red <b>You can't fit!</b>"
		else
			usr << "\red <b>The door is locked!</b>"

	else if(!src.occupants["pilot"] && src.occupants["passenger"])
		if(allow2enter)
			usr << "\blue <B>You scooch over into the pilot's seat.</B>"
			if(enter_after(20,usr))
				moved_inside(usr)
				src.occupants["passenger"] = null
			else
				usr << "You stop entering the spacepod."
			return
		else
			usr << "\red <b>The door is locked!</b>"

	else if(!src.occupants["pilot"] && !src.occupants["passenger"])
		visible_message("\blue [usr] starts to climb into [src.name].")
		if(enter_after(40,usr))
			if(!src.occupants["pilot"])
				moved_inside(usr)
			else if(src.occupants["pilot"]!=usr)
				usr << "[src.occupants["pilot"]] was faster. Try better next time, loser."
		else
			usr << "You stop entering the spacepod."
		return

/obj/spacepod/verb/exit_pod()
	set name = "Exit Pod"
	set category = "Spacepod"
	set src = usr.loc

	if( usr == src.occupants["pilot"] )
		var/mob/pilot = src.occupants["pilot"]
		inertia_dir = 0 // engage reverse thruster and power down pod
		pilot.loc = src.loc
		src.occupants["pilot"] = null
	else if( usr == src.occupants["passenger"] )
		var/mob/passenger = src.occupants["passenger"]
		passenger.loc = src.loc
		src.occupants["passenger"] = null


/obj/spacepod/verb/exit_pod2()
	if(src.occupants["pilot"] == usr)
		set name = "Eject Occupant"
		set category = "Spacepod"
		set src = usr.loc

		var/chair = input( usr, "Which occupant seat would you like to eject?", "Eject Whom?", null ) in occupants

		var/mob/passenger = occupants[chair]
		if( passenger )
			occupants_announce( "Occupant [passenger] has been ejected from the pod." )
			passenger.loc = src.loc
			src.throw_at( get_distant_turf( get_turf(src), 4, dir ), 4, 4, passenger.throw_speed, null)
			src.occupants["passenger"] = null

/obj/spacepod/verb/locksecondseat()
	if( occupants["pilot"] == usr )
		set name = "Lock Doors"
		set category = "Spacepod"
		set src = usr.loc

		if(src.allow2enter)
			src.allow2enter = 0
			occupants_announce( "Spacepod exterior doors locked." )
		else
			src.allow2enter = 1
			occupants_announce( "Spacepod exterior doors unlocked." )

/obj/spacepod/verb/toggleDoors()
	if(src.occupants["pilot"])
		set name = "Toggle Nearby Pod Doors"
		set category = "Spacepod"
		set src = usr.loc

		for(var/obj/machinery/door/poddoor/P in oview(3,src))
			if(istype(P, /obj/machinery/door/poddoor/three_tile_hor) || istype(P, /obj/machinery/door/poddoor/three_tile_ver) || istype(P, /obj/machinery/door/poddoor/four_tile_hor) || istype(P, /obj/machinery/door/poddoor/four_tile_ver))
				var/mob/living/carbon/human/L = usr
				if(P.check_access(L.get_active_hand()) || P.check_access(L.wear_id))
					if(P.density)
						P.open()
						return 1
					else
						P.close()
						return 1
				occupants["pilot"] << "<span class='warning'>Access denied.</span>"
				return
		occupants["pilot"] << "<span class='warning'>You are not close to any pod doors.</span>"
		return

/obj/spacepod/verb/autopilot()
	if( equipment_system.autopilot )
		if( src.occupants["pilot"] == usr )
			set name = "Activate Autopilot"
			set category = "Spacepod"
			set src = usr.loc

			equipment_system.autopilot.prompt()


/obj/spacepod/verb/fireWeapon()
	if( equipment_system.weapon_system )
		if( src.occupants["pilot"] == usr )
			set name = "Fire Pod Weapons"
			set desc = "Fire the weapons."
			set category = "Spacepod"
			set src = usr.loc
			if( equipment_system )
				if( equipment_system.weapon_system )
					equipment_system.weapon_system.fire_weapons()
				else
					occupants_announce( "ERROR: This pod does not have any active weapon systems.", 2 )

obj/spacepod/verb/toggleLights()
	if( src.occupants["pilot"] == usr )
		set name = "Toggle Lights"
		set category = "Spacepod"
		set src = usr.loc

		lightsToggle()

/obj/spacepod/verb/use_warp_beacon()
	set name = "Use Nearby Warp Beacon"
	set category = "Spacepod"
	set src = usr.loc

	for(var/obj/machinery/computer/gate_beacon_console/C in orange(usr.loc, 3)) // Finding suitable VR platforms in area
		if(alert(usr, "Would you like to interface with: [C]?", "Confirm", "Yes", "No") == "Yes")
			C.gate_prompt( occupants["pilot"] )
			occupants_announce( "Activated charging sequence for nearby bluespace beacon." )

/obj/spacepod/proc/lightsToggle()
	lights = !lights
	if(lights)
		SetLuminosity(luminosity + lights_power)
	else
		SetLuminosity(luminosity - lights_power)
	occupants_announce( "Spacepod lights toggled [lights?"on":"off"]." )
	return

/obj/spacepod/proc/enter_after(delay as num, var/mob/user as mob, var/numticks = 5)
	var/delayfraction = delay/numticks

	var/turf/T = user.loc

	for(var/i = 0, i<numticks, i++)
		sleep(delayfraction)
		if(!src || !user || !user.canmove || !(user.loc == T))
			return 0

	return 1

/datum/global_iterator/pod_preserve_temp  //normalizing cabin air temperature to 20 degrees celsium
	delay = 20

	process(var/obj/spacepod/spacepod)
		if(spacepod.cabin_air && spacepod.cabin_air.volume > 0)
			var/delta = spacepod.cabin_air.temperature - T20C
			spacepod.cabin_air.temperature -= max(-10, min(10, round(delta/4,0.1)))
		return

/datum/global_iterator/pod_tank_give_air
	delay = 15

	process(var/obj/spacepod/spacepod)
		if(spacepod.internal_tank)
			var/datum/gas_mixture/tank_air = spacepod.internal_tank.return_air()
			var/datum/gas_mixture/cabin_air = spacepod.cabin_air

			var/release_pressure = ONE_ATMOSPHERE
			var/cabin_pressure = cabin_air.return_pressure()
			var/pressure_delta = min(release_pressure - cabin_pressure, (tank_air.return_pressure() - cabin_pressure)/2)
			var/transfer_moles = 0
			if(pressure_delta > 0) //cabin pressure lower than release pressure
				if(tank_air.temperature > 0)
					transfer_moles = pressure_delta*cabin_air.volume/(cabin_air.temperature * R_IDEAL_GAS_EQUATION)
					var/datum/gas_mixture/removed = tank_air.remove(transfer_moles)
					cabin_air.merge(removed)
			else if(pressure_delta < 0) //cabin pressure higher than release pressure
				var/datum/gas_mixture/t_air = spacepod.get_turf_air()
				pressure_delta = cabin_pressure - release_pressure
				if(t_air)
					pressure_delta = min(cabin_pressure - t_air.return_pressure(), pressure_delta)
				if(pressure_delta > 0) //if location pressure is lower than cabin pressure
					transfer_moles = pressure_delta*cabin_air.volume/(cabin_air.temperature * R_IDEAL_GAS_EQUATION)
					var/datum/gas_mixture/removed = cabin_air.remove(transfer_moles)
					if(t_air)
						t_air.merge(removed)
					else //just delete the cabin gas, we're in space or some shit
						del(removed)
		else
			return stop()
		return

/obj/spacepod/Move(NewLoc, Dir = 0, step_x = 0, step_y = 0)
	//if( istype( get_turf( src ), /turf/space/bluespace ))// no moving in bluespace
	//	return

	if( move_tick < ticks_per_move )
		move_tick++
		return

	move_tick = 0


	if( equipment_system.engine_system )
		if( !equipment_system.engine_system.cycle() )
			return

	..()

	if(dir == 1 || dir == 4)
		src.loc.Entered(src)

/obj/spacepod/proc/Process_Spacemove(var/check_drift = 0, mob/user)
	var/dense_object = 0
	if(!user)
		for(var/direction in list(NORTH, NORTHEAST, EAST))
			var/turf/cardinal = get_step(src, direction)
			if(istype(cardinal, /turf/space))
				continue
			dense_object++
			break
	if(!dense_object)
		return 0
	inertia_dir = 0
	return 1

/obj/spacepod/relaymove(mob/user, direction)
	if( src.occupants["pilot"] == usr )
		handlerelaymove(user, direction)
	else
		return

/obj/spacepod/proc/handlerelaymove(mob/user, direction)
	var/moveship = 1
	var/obj/item/weapon/cell/battery = equipment_system.battery

	if(health && empcounter == 0)
		src.dir = direction
		switch(direction)
			if(1)
				if(inertia_dir == 2)
					inertia_dir = 0
					moveship = 0
			if(2)
				if(inertia_dir == 1)
					inertia_dir = 0
					moveship = 0
			if(4)
				if(inertia_dir == 8)
					inertia_dir = 0
					moveship = 0
			if(8)
				if(inertia_dir == 4)
					inertia_dir = 0
					moveship = 0
		if(moveship)
			step(src, direction)
			if(istype(src.loc, /turf/space))
				inertia_dir = direction
	else
		if(!battery)
			user << "<span class='warning'>No energy cell detected.</span>"
		else if(battery.charge < 3)
			user << "<span class='warning'>Not enough charge left.</span>"
		else if(!health)
			user << "<span class='warning'>She's dead, Jim</span>"
		else if(empcounter != 0)
			user << "<span class='warning'>The pod control interface isn't responding. The console indicates [empcounter] seconds before reboot.</span>"
		else
			user << "<span class='warning'>Unknown error has occurred, yell at pomf.</span>"
		return 0
	battery.charge = max(0, battery.charge - 3)

/obj/effect/landmark/spacepod/random
	name = "spacepod spawner"
	invisibility = 101
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"
	anchored = 1

/obj/effect/landmark/spacepod/random/New()
	..()

/obj/spacepod/verb/fly_up()
	set category = "Spacepod"
	set name = "Fly Upwards"
	set src = usr.loc

	var/turf/ground = get_turf( src )
	if( !istype( ground.loc, /area/space ))
		occupants["pilot"] << "<span class='warning'>\The ceiling is in the way!</span>"

	var/turf/controllerlocation = locate(1, 1, z)
	for(var/obj/effect/landmark/zcontroller/controller in controllerlocation)
		if(controller.up)
			var/turf/upwards = locate(src.x, src.y, controller.up_target)

			if( !upwards.density )
				src.loc = upwards
				occupants["pilot"] << "You cruise upwards."
			else
				occupants["pilot"] << "<span class='warning'>There is a [upwards] in the way!</span>"
		else
			occupants["pilot"] << "<span class='warning'>There's nothing of interest above you!</span>"

/obj/spacepod/verb/fly_down()
	set category = "Spacepod"
	set name = "Fly Downwards"
	set src = usr.loc

	var/turf/ground = get_turf( src )
	if( !istype( ground, /turf/space ) && !istype( ground,/turf/simulated/floor/open ))
		occupants["pilot"] << "<span class='warning'>\The [ground] is in the way!</span>"

	var/turf/controllerlocation = locate(1, 1, z)
	for(var/obj/effect/landmark/zcontroller/controller in controllerlocation)
		if(controller.down)
			var/turf/below = locate(src.x, src.y, controller.down_target)

			if( !below.density )
				src.loc = below
				occupants["pilot"] << "You cruise downwards."
			else
				occupants["pilot"] << "<span class='warning'>There is a [below] in the way!</span>"
		else
			occupants["pilot"] << "<span class='warning'>There's nothing of interest below you!!</span>"

/obj/spacepod/verb/sector_locate()
	set category = "Spacepod"
	set name = "Triangulate Sector"
	set src = usr.loc

	usr << "<span class='notice'>Triangulating sector location through bluespace beacons, please standby... (This may take up to a minute)</span>"
	var/cur_z = src.z
	spawn( rand( 300, 600 ))
		if( cur_z != src.z )
			usr << "<span class='warning'>ERROR: Inaccurate readings, cannot calculate sector. Please stay still next time.</span>"
			return

		var/obj/effect/map/sector = map_sectors["[z]"]
		if( !sector )

			usr << "<span class='warning'>ERROR: Critical error with the bluespace network!</span>"
			return

		usr << "<span class='notice'>You are currently located in Sector [SYSTEM_DESIGNATION]-[sector.x]-[sector.y]</span>"

/obj/spacepod/command
	name = "\improper command spacepod"
	desc = "A sleek command space pod."
	icon_state = "pod_com"

/obj/spacepod/command/New()
	..()
	equipment_system.equip( new /obj/item/pod_parts/armor/command )

/obj/spacepod/command/complete/New()
	..()
	equipment_system.equip( new battery_type )
	equipment_system.equip( new /obj/item/device/spacepod_equipment/engine )

/obj/spacepod/security
	name = "\improper security spacepod"
	desc = "An armed security spacepod with reinforced armor plating."
	icon_state = "pod_sec"

/obj/spacepod/security/New()
	..()
	equipment_system.equip( new /obj/item/pod_parts/armor/security )

/obj/spacepod/security/complete/New()
	..()
	equipment_system.equip( new /obj/item/device/spacepod_equipment/engine )
	equipment_system.equip( new /obj/item/device/spacepod_equipment/shield )
	equipment_system.equip( new /obj/item/device/spacepod_equipment/weaponry/taser )
	equipment_system.equip( new /obj/item/device/spacepod_equipment/misc/tracker )

	equipment_system.misc_system.enabled = 1
	return

/obj/spacepod/dev/New()
	..()
	equipment_system.max_size = 1000
	equipment_system.equip( new /obj/item/device/spacepod_equipment/engine )
	equipment_system.equip( new /obj/item/device/spacepod_equipment/weaponry/taser )
	equipment_system.equip( new /obj/item/device/spacepod_equipment/weaponry/burst_taser )
	equipment_system.equip( new /obj/item/device/spacepod_equipment/weaponry/laser )
	equipment_system.equip( new /obj/item/pod_parts/armor/security )
	equipment_system.equip( new /obj/item/weapon/cell/super )
	equipment_system.equip( new /obj/item/device/spacepod_equipment/shield )
	equipment_system.equip( new /obj/item/device/spacepod_equipment/misc/tracker )
	equipment_system.misc_system.enabled = 1
	return

#undef DAMAGE
#undef FIRE