/obj/structure/flora/tree/pine/christmas
	var/decoration_count = 0
	var/max_decorations = 0
	var/list/contributers
	icon = 'icons/obj/flora/pinetrees.dmi'
	icon_state = "pine_1"
	name = "Pine Tree"
	desc = "A mysterious pine tree. It looks like it is going to die."

	var/dying = 1
	var/joyous = 0
	var/christmas = 0

/obj/structure/flora/tree/pine/christmas/New()
	..()
	//Don't know how many we'll have so :>
	for(var/type in subtypes( /obj/item/weapon/spec_decoration ))
		max_decorations++

	contributers = list()

	update_icon()

/obj/structure/flora/tree/pine/christmas/update_icon()
	if( christmas )
		icon_state = "pine_c"
		name = "Christmas Tree"
	else
		icon_state = "pine_1"
		name = "Pine Tree"

	desc = "A mysterious [joyous ? "joyous " : ""][src]. [dying ? "It looks like it is going to die" : "" ]!"

/examine(mob/user)
	..(user)

	if( decoration_count )
		user << "It is covered with [decoration_count] of [max_decorations]."

/obj/structure/flora/tree/pine/christmas/attackby( var/obj/item/O as obj, var/mob/user as mob )
	if( !O )
		return

	if( !user )
		return

	if( istype( O, /obj/item/weapon/spec_decoration ))
		if( !( user in contributers ))
			contributers.Add( user )
		decoration_count++
		user << "You add \the [O] to the [src]"
		qdel( O )

		for( var/mob/living/M in orange( src, 7 ))
			if( M != user )
				M << "You feel the holiday spirit build as [user.name] adds \the [O] to the [src]."

	if( dying && ispath( O, /obj/item/weapon/reagent_containers/glass/fertilizer ))
		joyous = 1
		dying = 0
		user << "You pour the [O] onto the [src]!"

		qdel( O )

		if( log_acc_item_to_db( user.ckey, "Christmas Sweater" ))
			user << "<span class='notice'><b>Christmas Uber Cheer - Congratulations! You grew the tree to be big and strong!. A Christmas Sweater has been added to your account as a reward.</b></span>"
		else
			user << "<span class='notice'><b>Christmas Uber Cheer - You've already collected this item. Sorry!</b></span>"
	else if( !dying && ispath( O, /obj/item/weapon/reagent_containers/glass/fertilizer ))
		user << "The [src] already looks healthy!"

	if(decoration_count == max_decorations && !christmas)
		christmas = 1

		for(var/mob/M in contributers)
			if( log_acc_item_to_db( M.ckey, "Holiday Wreath" ))
				M << "<span class='notice'><b>Christmas Cheer - Congratulations! You helped decorate the Christmas Tree and raise the holiday spirit! A Holiday Wreath has been added to your account as a reward.</b></span>"
			else
				M << "<span class='notice'><b>Christmas Cheer - You've already collected this item. Sorry!</b></span>"

    	//Spawn the ghost here
		new /mob/living/simple_animal/holiday_spirit( get_turf( src ))

	update_icon()