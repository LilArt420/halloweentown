-- Halloween Town  --  client-side item names.
--
-- 12990 (Pet_Egg_Scroll7) shows as "Halloween Spooky Pack". The sprite is the
-- item's own; only the name and description change.
--
-- tbl_override is read before the base table and the first description for
-- an id wins, so these take precedence.

tbl_override = {
	[12990] = {
		unidentifiedDisplayName = "Halloween Spooky Pack",
		unidentifiedResourceName = "성속성알",
		unidentifiedDescriptionName = { "" },
		identifiedDisplayName = "Halloween Spooky Pack",
		identifiedResourceName = "성속성알",
		identifiedDescriptionName = {
			"A little pack Jakk swears he fished out of Blair's cauldron.",
			"Something inside it is wriggling.",
			"Open it to find out what followed you home from Halloween Town.",
			"_______________________",
			"^0000CCWeight:^000000 1"
		},
		slotCount = 0,
		ClassNum = 0,
		costume = false
	},
}
