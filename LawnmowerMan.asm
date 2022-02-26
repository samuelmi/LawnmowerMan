.data 0x10010000                # Start of data memory
a_sqr:  .space 4
a:  .word 3

.text 0x00400000                # Start of instruction memory
.globl main

main:
	lui     $sp, 0x1001         # Initialize stack pointer to the 1024th location above start of data
   	ori     $sp, $sp, 0x1000    # top of the stack will be one word below
                                #   because $sp is decremented first.
    	addi    $fp, $sp, -4        # Set $fp to the start of main's stack frame
	
	li 	$s0, 10			# $s0 = Player row, initialized to top row of gameboard
	li	$s1, 2			# $s1 = Player col, initialized to left-most col of gameboard
	li	$s5, 2			# $s5 = Player direction (0 = stalled, 1 = left, 2 = right, 3 = up, 4 = down)
	li	$s4, 1			# $s4 = Number of tiles mowed by player, initialized to 1 (the square you start in
	
	li 	$s2, 19			# $s2 = Mosquito row, initialized to middle row of gameboard
	li	$s3, 20			# $s3 = Mosquito col, initialized to middle col of gameboard
	li	$s7, 0			# Initialize game timer to 0
	
        jal	clear_gameboard		# Intialize the gameboard (erases previous game)   
       	jal 	title_screen     	# Draw title screen
       	
       	lw	$a0, high_score
	li	$a1, 7
	li	$a2, 7
	jal	write_num_to_screen	# Draws high score (best time) to screen 
       	
       	jal	draw_player
	
	li	$t7, 0			# $t7 = index of music loop, init to 0
	
title_loop:
	li 	$a0, 3			# Need to reinitialize $a0 arg as it was overwritten
	jal 	pause			
	jal	get_key			# Gets keyboard input (pause_and_get_key is buggy)
	la	$t0, ($v0)		# $t0 = key index
	jal	generate_random_number	# Generate random number
	
	# Plays music
	jal 	play_music
	
	bne	$t0, 2, title_loop	# Loop until 'd' key is pressed
	
	jal	sound_off		# Stop music
	jal	clear_gameboard		# Intialize the gameboard (erases title)
	lw	$s6, adjusted_random_number # Initialize mosquito direction
		
	jal 	draw_mosquito
	li	$t0, 0			# 1 = move player, 0 = don't move player
game_loop:
	beq	$s4, 648, game_won	# Checks for if game is won
	li	$a0, 5		
	jal	pause_and_getkey	# Gets keyboard input while also pausing for 0.25 seconds
	 
	beq	$v0, 0, no_input	# Skip updating player direction if no input given
	beq	$s5, $0, no_input	# If player is stalled, don't overwrite their direction
	la	$s5, ($v0)		# Otherwise set $s5 (player's direction) to $v0 (returned code from get_key)
no_input:
	beq	$t0, $0, skip_player_move	# Skip player move every other tick
	jal	move_player		# Attempts to move player in given direction and if possible, updates them on screen
skip_player_move:
	jal	move_mosquito		# Moves mosquito/changes course if hits wall
	addi	$s7, $s7, 1		# Increments game timer
	jal	update_timer		# Redraws the game timer to screen

	la	$t1, ($t0)		# $t1 = $t0 (sets before altering $t0)
	li	$t0, 1
	beq	$t1, $0, tick_is_odd	# if $t1 == 0, then $t0 = 1, else $t0 = 0
	li	$t0, 0
tick_is_odd:
	jal	generate_random_number	# Generate random number
	jal	play_game_sounds
	j	game_loop		# Loop back to beginning
   
.data
high_score:	# High score is stored here
.word 999	# Value defaulted to max
.text
game_won:
	jal	sound_off				# Stop all sound being played
	li 	$a1, 2					# $a1 = col number (initialized to col 2)
	li 	$a2, 10					# $a2 = row number (initialized to row 10)
	# Wipe board animation
draw_loop_2:
	li	$a0, 1
	jal 	pause					
	li	$a0, 0x28				# Unmowed grass keycode
	jal 	putChar_atXY				# Draw unmowed grass sprite
	addi	$a1, $a1, 1				# Increment column
	bne	$a1, 38, draw_loop_2			# Keep looping until col = 38
	li	$a1, 2					# Reset col back to 2
	addi	$a2, $a2, 1				# Increment row
	bne	$a2, 28, draw_loop_2			# Keep looping until row = 28 
	
	# Checks high score vs timer
	srl	$t1, $s7, 3				# $t1 = timer / 8
	lw	$t0, high_score
	
	slt	$1, $t1, $t0				# $1 = timer < best time
	
	beq	$1, $0, main				# Checks if timer is smaller than high score
	sw	$t1, high_score				# Sets high_score to game timer if time was better than best time
	j 	main					# Loop back to main
       	    	    	
       	
    ###############################
    # END using infinite loop     #
    ###############################
    
                # program won't reach here, but have it for safety
end:
    	j   end             # infinite loop "trap" because we don't have syscalls to exit


######## END OF MAIN #################################################################################
.data
player_old_dir:		# Stores player's old directin before being stalled
.word 0
player_stall_count:	# Stores how many player moves player has been stalled for
.word 0
.text


	#####################################################################
	# Proc for moving the player                                        #
	# Will check what direction the playeris moving in and if possible, # 
	# will move him in that direction by updating the $s0 (player row)  #
	# and $s1 (player col) registers                                    # 
	#####################################################################
move_player:
	addi	$sp, $sp, -12
	sw	$ra, 8($sp)
	sw	$t0, 4($sp)
	sw	$t1, 0($sp)
	
	beq 	$s5, 1, move_player_left		# Checks which direction to move player in
	beq	$s5, 2, move_player_right
	beq	$s5, 3, move_player_up
	beq	$s5, 4, move_player_down
	j	player_stalled				# If direction = 0, keep player in place
										
move_player_left:					# $t0 = players next row, $t1 = players next col. Will use these values to check if move is viable and safe
	la	$t0, ($s0)				# $t0 = player row
	addi	$t1, $s1, -1				# $t1 = player col - 1
	j	player_stalled
move_player_right:
	la	$t0, ($s0)				# $t0 = player row
	addi	$t1, $s1, 1				# $t1 = player col + 1	
	j 	player_stalled
move_player_up:
	addi	$t0, $s0, -1				# $t0 = player row - 1
	la	$t1, ($s1)				# $t1 = player col
	j	player_stalled
move_player_down:
	addi	$t0, $s0, 1				# $t0 = player row + 1
	la	$t1, ($s1)				# $t1 = player col
player_stalled:
	beq	$s5, 0, handle_player_stalled		# Increments stall counter and skips player's move
	la	$a1, ($t1)
	la	$a2, ($t0)				
	jal	getChar_atXY				# $v0 = bitmap code for sprite in player's next location
	beq	$v0, 0x28, player_mowed_grass		# If player moving into unmowed grass
	beq	$v0, 0x29, player_move_safe		# If player moving into mowed grass
	

	beq	$v0, 0x2C, skip_move			# Skip player's move if it would put him into a wall
	# Otherwise player is hitting the mosquito	
	jal	player_hit_mosquito			# Handles player's collision with mosquito
	j 	skip_move

player_mowed_grass:
	addi	$s4, $s4, 1				# Increments the number of grass mowed
player_move_safe:		
	# Erases player from old location and replaces with mowed grass
	li	$a0, 0x29				# Bitmap code for mowed grass sprite
	la	$a1, ($s1)				# $a1 = player's old col
	la 	$a2, ($s0)				# $a2 = player's old row
	jal	putChar_atXY				# Replaces player

	# Updates player's row/col positioning
	la 	$s0, ($t0)				# Player row = player's next row
	la	$s1, ($t1)				# Player col = player's next col
	
	# Redraws the player in new location
	jal	draw_player				# Draw player
skip_move:	
	lw	$ra, 8($sp)
	lw	$t0, 4($sp)
	lw	$t1, 0($sp)
	addi	$sp, $sp, 12
	jr	$ra 

handle_player_stalled:
	lw	$t0, player_stall_count
	bne	$t0, 16, increment_stall_count		# If player hasn't been stalled for 16 cycles move on
	lw	$s5, player_old_dir			# Resets player's old direction
	j 	skip_move
increment_stall_count:
	addi	$t0, $t0, 1				# Increment stall count
	sw	$t0, player_stall_count			# Store updated stall count
	j 	skip_move

	#########################################
	# Proc for drawing player on the screen #
	#########################################
draw_player:
	addi	$sp, $sp, -4
	sw	$ra, 0($sp)
	
	li	$a0, 0x26				# $a0 = Bitmap code for player character
	la	$a1, ($s1)				# $a1 = Player col
	la	$a2, ($s0)				# $a2 = Player row
	jal	putChar_atXY				# Draw player
	
	lw	$ra, 0($sp)
	addi	$sp, $sp, 4
	jr	$ra 

	################################
	# Proc for moving the mosquito #
	################################
move_mosquito:
	addi	$sp, $sp, -12
	sw	$ra, 8($sp)
	sw	$t0, 4($sp)
	sw	$t1, 0($sp)
	
	beq	$s6, 0, move_mosquito_up
	beq	$s6, 1, move_mosquito_up_r
	beq	$s6, 2, move_mosquito_r
	beq	$s6, 3, move_mosquito_dn_r
	beq	$s6, 4, move_mosquito_dn
	beq	$s6, 5, move_mosquito_dn_l
	beq	$s6, 6, move_mosquito_l
	beq	$s6, 7, move_mosquito_up_l
	j	end
	
	# $t0 = mosquito new row
	# $t1 = mosquito new col
move_mosquito_up:
	addi	$t0, $s2, -1				# $t0 = row - 1
	la	$t1, ($s3)				# $t1 = col
	j	check_mosquito_move
move_mosquito_up_r:
	addi	$t0, $s2, -1				# $t0 = row - 1
	addi	$t1, $s3, 1				# $t1 = col + 1
	j	check_mosquito_move
move_mosquito_r:
	la	$t0, ($s2)				# $t0 = row
	addi	$t1, $s3, 1				# $t1 = col + 1
	j	check_mosquito_move
move_mosquito_dn_r:
	addi	$t0, $s2, 1				# $t0 = row + 1
	addi	$t1, $s3, 1				# $t1 = col + 1
	j	check_mosquito_move
move_mosquito_dn:
	addi	$t0, $s2, 1				# $t0 = row + 1
	la	$t1, ($s3)				# $t1 = col
	j	check_mosquito_move
move_mosquito_dn_l:
	addi	$t0, $s2, 1				# $t0 = row + 1
	addi	$t1, $s3, -1				# $t1 = col - 1
	j	check_mosquito_move
move_mosquito_l:
	la	$t0, ($s2)				# $t0 = row
	addi	$t1, $s3, -1				# $t1 = col - 1
	j	check_mosquito_move
move_mosquito_up_l:
	addi	$t0, $s2, -1				# $t0 = row - 1
	addi	$t1, $s3, -1				# $t1 = col - 1
	
	# If mosquito hits a barrier (player or wall) don't move this round and choose new direction
check_mosquito_move:
	la	$a1, ($t1)
	la	$a2, ($t0)
	jal	getChar_atXY				# Gets character at mosquito's next location
	beq	$v0, 0x2C, choose_new_direction		# Checks if mosquito hits wall
	bne	$v0, 0x26, mosquito_move_safe		# Checks if mosquito hits player
	jal	player_hit_mosquito			# Handle colision
	j	choose_new_direction			# Choose new direction for mosquito
mosquito_move_safe:
	# Erases mosquito from old location and replaces with appropiate sprite
	la	$a1, ($s3)
	la	$a2, ($s2)
	jal	getChar_atXY				# Gets bitmap to determine which moquito sprite was used
	li	$a0, 0x28				# Bitmap code for unmowed grass sprite
	beq	$v0, 0x2A, replace_mosquito		# If mosquito has unmowed background, replace with unmowed grass
	li	$a0, 0x29				# Bitmap code for mowed grass sprite
replace_mosquito:
	jal	putChar_atXY				# Replaces mosquito
	
	# Updates $s2 and $s3 with mosquito's new location
	la	$s2, ($t0)
	la	$s3, ($t1)
	
	# Redraws mosquito
	jal	draw_mosquito
	lw	$t0, raw_random_number
	bne	$t0, 30, end_mosquito_move		# Approx 3% chance of mosquito changing direction
		
choose_new_direction:
	lw	$s6, adjusted_random_number

end_mosquito_move:
	lw	$ra, 8($sp)
	lw	$t0, 4($sp)
	lw	$t1, 0($sp)
	addi	$sp, $sp, 12
	jr	$ra 
	
	###########################################
	# Proc for drawing mosquito on the screen #
	###########################################
draw_mosquito:
	addi	$sp, $sp, -4
	sw	$ra, 0($sp)
		
	la	$a1, ($s3)				# $a1 = Mosquito col
	la	$a2, ($s2)				# $a2 = Mosquito row
	jal	getChar_atXY				# Checks to see if character placing mosquito at is mowed or unmowed
	la 	$a0, 0x2A				# Defaults to unmowed background
	beq	$v0, 0x28, mosquito_unmowed
	la	$a0, 0x2B				# Bitmap code for mosquito sprite with mowed background
mosquito_unmowed:
	jal	putChar_atXY				# Draw mosquito
	
	lw	$ra, 0($sp)
	addi	$sp, $sp, 4
	jr	$ra
	
	######################################
	# Proc for drawing the title screen  #
	######################################
.data							# Store in data memory
# Bitmap codes used to draw "PRESS D TO BEGIN"
title_array:	
.word	0x19, 0x1B, 0x0E, 0x1C, 0x1C, 0x24, 0x0D, 0x24, 0x1D, 0X18, 0x24, 0x0B, 0x0E, 0x10, 0x12, 0x17
title_array_end:	    				# marks end title_array
.text       						# Switch back to writing instruction memory
title_screen:   
	addi	$sp, $sp, -12
	sw	$ra, 8($sp)
	sw	$t0, 4($sp)
	sw	$t1, 0($sp)
	
	la	$t0, title_array			# $t0 = i, starting address location of title_array
	la	$t1, title_array_end			# $t1 = Address location of the end of title_array
	li	$a1, 12					# $a1 = Col to write to, starts at col 13
	li	$a2, 19					# $a2 = Row to write to, Constant of 20
draw_title_loop:					
	lw	$a0, ($t0)				# $a0 = bitmap code from array
	jal	putChar_atXY				# Draw character on screen
	addi	$t0, $t0, 4				# Go to next array element
	addi	$a1, $a1, 1				# Increment the col to write to
	beq	$t0, $t1, draw_title_loop_exit		# If all elements have been loaded, exit loop
	j	draw_title_loop				
draw_title_loop_exit:
	lw	$ra, 8($sp)
	lw	$t0, 4($sp)
	lw	$t1, 0($sp)
	addi	$sp, $sp, 12
	jr	$ra 

	###################################################
	# Proc for setting gameboard to all unmowed grass #
	###################################################
clear_gameboard:
	addi	$sp, $sp, -4
	sw	$ra, 0($sp)

	li	$a0, 0x28				# Unmowed grass keycode
	li 	$a1, 2					# $a1 = col number (initialized to col 2)
	li 	$a2, 10					# $a2 = row number (initialized to row 10)
	
draw_loop:
	jal 	putChar_atXY				# Draw unmowed grass sprite
	addi	$a1, $a1, 1				# Increment column
	bne	$a1, 38, draw_loop			# Keep looping until col = 38
	li	$a1, 2					# Reset col back to 2
	addi	$a2, $a2, 1				# Increment row
	bne	$a2, 28, draw_loop			# Keep looping until row = 28
	
	lw	$ra, 0($sp)
	addi	$sp, $sp, 4
	jr	$ra 

	
	################################################################################################################################
	# Proc for generating a random number (0-6) and storing it in memory. This is done every "tick" in order to enforce randomness #
	################################################################################################################################
.data
raw_random_number:					# Address of the random number from 0 - 30
.word 0
adjusted_random_number:					# Address of the random number from 0 - 7
.word 0
.text
generate_random_number:
	addi	$sp, $sp, -16
	sw	$ra, 12($sp)
	sw	$t0, 8($sp)
	sw	$t1, 4($sp)
	sw	$t2, 0($sp)

	srl	$t1, $s7, 3				# $t1 = timer / 4

	lw	$t0, raw_random_number			# $t0 = old random number (from memory)
	addi	$t0, $t0, 59				# Adds 59 (prime) to old random number
	add	$t0, $t0, $s4				# Adds the number of tiles mowed to improve randomness
	add	$t0, $t0, $s5				# Adds player's direction to imrove randomness
	add	$t0, $t0, $t1				# Adds timer to improve randomness
	
mod_loop: 
	addi	$t0, $t0, -31				# $t0 = $t0 - 31
	slti	$1, $t0, 31				# $1 = $t0 < 31
	beq	$1, $0, mod_loop			# loop until $t0 < 31
	
	sw	$t0, raw_random_number			# Store random number back into memory
	
	# Adjusts random number to be anywhere from 0 to 7
	li	$t1, 0xFFFFFFF8				# $t1 = 1111_1111_1111_1111_1111_1111_1111_1000
	nor	$t0, $t0, $t1				# Removes top 29 bits (but also flips the first 3 bits)
	sw	$t0, adjusted_random_number		# Stores adjusted random number in memory
	
	lw	$t0, adjusted_random_number	
	
	lw	$ra, 12($sp)
	lw	$t0, 8($sp)
	lw	$t1, 4($sp)
	lw	$t2, 0($sp)
	addi	$sp, $sp, 16
	jr	$ra 
	

	##############################################################################################
	# Proc/Subroutine for playing music. The next note in array is played each time it's called	#
	# $a1 = index of note to play (increments by 4)						#
	# $v0 = next index of note to play								#	
	##############################################################################################
.data
music_array:
.word 429000, 429000, 0, 0, 0, 0, 429000, 429000, 0, 0, 0, 0, 429000, 429000, 0, 0, 0, 0, 191094, 191094, 191094, 191094, 191094, 191094, 0, 0, 0, 0, 170270, 170270, 170270, 170270, 170270, 170270, 170270, 170270, 170270, 170270, 170270, 170270, 0, 151676, 151676, 151676, 151676, 0, 151676, 151676, 0, 0, 0, 0, 151676, 151676, 0, 0, 0, 0, 143163, 143163, 143163, 143163, 143163, 143163, 0, 0, 0, 0, 127551, 127551, 127551, 127551, 0, 454545, 454545, 454545, 454545, 0, 454545, 454545, 0, 0, 0, 0, 255102, 255102, 255102, 255102, 0, 286368, 286368, 0, 0, 0, 0, 286368, 286368, 286368, 286368, 286368, 286368, 286368, 286368, 286368, 286368, 286368, 286368, 0, 286368, 286368, 286368, 286368, 0, 454545, 454545, 454545, 454545, 0, 191094, 191094, 191094, 191094, 0, 143163, 143163, 0, 0, 0, 0, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 0, 0, 0, 0, 0, 0, 191094, 191094, 191094, 191094, 0, 454545, 454545, 454545, 454545, 0, 255102, 255102, 255102, 255102, 255102, 255102, 255102, 255102, 0, 286368, 286368, 286368, 286368, 0, 0, 0, 0, 0, 0, 286368, 286368, 286368, 286368, 0, 454545, 454545, 454545, 454545, 0, 255102, 255102, 255102, 255102, 0, 286368, 286368, 0, 0, 0, 0, 255102, 255102, 255102, 255102, 255102, 255102, 255102, 255102, 0, 255102, 255102, 255102, 255102, 255102, 255102, 255102, 255102, 0, 340483, 340483, 340483, 340483, 0, 454545, 454545, 454545, 454545, 0, 429000, 429000, 429000, 429000, 429000, 429000, 429000, 429000, 0, 429000, 429000, 429000, 429000, 0, 191094, 191094, 191094, 191094, 191094, 191094, 191094, 191094, 191094, 191094, 191094, 191094, 191094, 191094, 191094, 191094, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 454545, 454545, 454545, 454545, 0, 454545, 454545, 0, 0, 0, 0, 255102, 255102, 255102, 255102, 0, 286368, 286368, 0, 0, 0, 0, 286368, 286368, 286368, 286368, 286368, 286368, 286368, 286368, 0, 0, 0, 0, 0, 0, 191094, 191094, 191094, 191094, 0, 143163, 143163, 143163, 143163, 0, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 0, 191094, 191094, 191094, 191094, 0, 227272, 227272, 227272, 227272, 0, 227272, 227272, 227272, 227272, 0, 227272, 227272, 227272, 227272, 0, 127551, 127551, 127551, 127551, 127551, 127551, 127551, 127551, 0, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 0, 0, 0, 0, 0, 0, 454545, 454545, 454545, 454545, 0, 255102, 255102, 255102, 255102, 0, 286368, 286368, 286368, 286368, 0, 255102, 255102, 255102, 255102, 255102, 255102, 255102, 255102, 0, 0, 0, 0, 0, 0, 0, 0, 454545, 454545, 454545, 454545, 454545, 454545, 0, 0, 0, 0, 0, 0, 0, 0, 429000, 429000, 429000, 429000, 429000, 429000, 429000, 429000, 0, 0, 0, 0, 0, 0, 191094, 191094, 191094, 191094, 191094, 191094, 191094, 191094, 0, 191094, 191094, 191094, 191094, 0, 170270, 170270, 170270, 170270, 0, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 151676, 0, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 0, 0, 0, 0, 0, 0, 454545, 454545, 454545, 454545, 0, 227272, 227272, 227272, 227272, 227272, 227272, 227272, 227272, 0, 214500, 214500, 214500, 214500, 0, 227272, 227272, 227272, 227272, 227272, 227272, 0, 0, 0, 0, 127551, 127551, 127551, 127551, 127551, 127551, 127551, 127551, 0, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 143163, 0, 170270, 170270, 170270, 170270, 170270, 170270, 170270, 170270, 170270, 170270, 170270, 170270, 0, 0, 0, 0, 0, 0, 227272, 227272, 227272, 227272, 0, 227272, 227272, 227272, 227272, 0, 227272, 227272, 227272, 227272, 0, 214500, 214500, 214500, 214500, 0, 227272, 227272, 227272, 227272, 227272, 227272, 227272, 227272, 0, 127551, 127551, 127551, 127551, 0, 127551, 127551, 127551, 127551, 0, 127551, 127551, 127551, 127551, 0, 135135, 135135, 135135, 135135, 0, 135135, 135135, 0, 0, 0, 0, 135135, 135135, 0, 0, 0, 0, 135135, 135135, 0, 0, 0, 0, 127551, 127551, 0, 0, 0, 0, 227272, 227272, 227272, 227272, 227272, 227272, 227272, 227272, 0, 127551, 127551, 127551, 127551, 127551, 127551, 127551, 127551, 127551, 127551, 127551, 127551, 127551, 127551, 127551, 127551, 127551, 127551, 127551, 127551, 0
music_array_end:
music_index:
.word 0
.text
play_music:
	addi	$sp, $sp, -16
	sw	$ra, 12($sp)
	sw	$t0, 8($sp)
	sw	$t1, 4($sp)
	sw	$t2, 0($sp)
	
	la	$t0, music_array			# $t0 = base address of music array
	la	$t1, music_array_end			# $t1 = address of the end of the music array
	lw	$t2, music_index			# $t2 = index of music
	
	add	$t0, $t0, $t2				# $t0 = address of tone to play in array
	lw 	$a0, ($t0)				# $a0 = period of tone to play
	jal	put_sound
	addi	$t2, $t2, 4				# Increment index by 4 to next array address
	addi	$t0, $t0, 4				# $t0 = address of next tone to play
	bne	$t0, $t1, end_play_music		# Checks to see if it needs to loop back over on itself (end of array reached)
	li	$t2, 0					# Resets index of note back to 0
end_play_music:	
	sw	$t2, music_index			# Store index back in ram

	lw	$ra, 12($sp)
	lw	$t0, 8($sp)
	lw	$t1, 4($sp)
	lw	$t2, 0($sp)
	addi	$sp, $sp, 16
	jr	$ra 
	
###############################################
# Proc for updating game timer on screen	#
# For ease of viewing, game timer on screen	#
# is the internal game timer / 4		#
###############################################
update_timer:
	addi	$sp, $sp, -4
	sw	$ra, 0($sp)
	
	srl	$a0, $s7, 3				# $a0 = timer / 4
	li	$a1, 36
	li	$a2, 7
	jal	write_num_to_screen
	
	lw	$ra, 0($sp)
	addi	$sp, $sp, 4
	jr	$ra 
##############################################################
# Proc for converting value to decimal and writing to screen #
# $a0 = number to convert									 #
# $a1 = col of far-left digit to be written on screen		 #
# $a2 = row of digits to be writen on screen			     #  
##############################################################
write_num_to_screen:
	addi	$sp, $sp, -20
	sw	$ra, 16($sp)
	sw	$t0, 12($sp)
	sw	$t1, 8($sp)
	sw	$t2, 4($sp)
	sw	$t3, 0($sp)
	
	li	$t0, 0					# $t0 = num in hundreds place
	li	$t1, 0					# $t1 = num in tens place
	li	$t2, 0					# $t2 = num in ones place		

hundreds_place_loop:
	addi	$t3, $a0, -100				# $t3 = num - 100
	
	slt	$1, $t3, $0				# $1 = $t3 < 0
	bne	$1, $0, tens_place_loop			# If subtracting 100 made $t3 negative, move on
	
	la	$a0, ($t3)				# $a0 = $t3
	addi	$t0, $t0, 1				# Increments num in hundreds place
	j	hundreds_place_loop		
tens_place_loop:
	addi	$t3, $a0, -10				# $t3 = num - 10
	
	slt	$1, $t3, $0				# $1 = $t3 < 0
	bne	$1, $0, ones_place_loop			# If subtracting 10 made $t3 negative, move on
	
	la	$a0, ($t3)				# $a0 = $t3
	addi	$t1, $t1, 1				# Increments num in tens place
	j	tens_place_loop	
ones_place_loop:
	addi	$t3, $a0, -1				# $t3 = num - 1
	
	slt	$1, $t3, $0				# $1 = $t3 < 0
	bne	$1, $0, write_nums			# If subtracting 1 made $t3 negative, move on
	
	la	$a0, ($t3)				# $a0 = $t3
	addi	$t2, $t2, 1				# Increments num in ones place
	j	ones_place_loop		
write_nums:
	la	$a0, ($t0)				# $a0 = num in hundreds place
	jal	putChar_atXY				# Writes digit in hundreds place
	la	$a0, ($t1)				# $a0 = num in tens place
	addi	$a1, $a1, 1				# Increments col by 1
	jal	putChar_atXY				# Writes digit in tens place
	la	$a0, ($t2)				# $a0 = num in ones place
	addi	$a1, $a1, 1				# Increments col by 1
	jal 	putChar_atXY				# Writes digit in ones place

	lw	$ra, 16($sp)
	lw	$t0, 12($sp)
	lw	$t1, 8($sp)
	lw	$t2, 4($sp)
	lw	$t3, 0($sp)
	addi	$sp, $sp, 20
	jr	$ra 

###############################################################################
# Proc to play game sound effects depending on whats occurring in-game	#
###############################################################################
play_game_sounds:
	addi	$sp, $sp, -8
	sw	$ra, 4($sp)
	sw	$t0, 0($sp)
	
	beq	$s5, $0, skip_sound			# Don't play lawnmower sound if player is stalled
	
	li	$t0, 0xFFFFFFFE				# $t1 = 1111_1111_1111_1111_1111_1111_1111_1110
	nor	$t0, $t0, $s7				# $t0 = $0 on odd clock ticks ($t0 = is_odd)
	
	beq	$t0, $0, play_a_sharp
	li	$a0, 4000000
	j	play_g_sharp
play_a_sharp:
	li	$a0, 3448275
play_g_sharp:
	jal	put_sound				# Plays lawnmower sound effect
	j	exit_play_game_sounds
skip_sound:
	jal 	sound_off
exit_play_game_sounds:	
	lw	$ra, 4($sp)
	lw	$t0, 0($sp)
	addi	$sp, $sp, 8
	jr	$ra

###################################################
# Proc for handling when player hits the mosquito #
###################################################
player_hit_mosquito:
	addi	$sp, $sp, -4
	sw	$ra, 0($sp)
	
	beq	$s5, $0, end_player_hit_mosquito	# No "double dipping" on player hitting mosquito (prevents infinite loops)
	
	sw	$0, player_stall_count			# Sets player_stall_count to 0
	sw	$s5, player_old_dir			# Sets player_old_dir to last direction before being stalled
	li	$s5, 0					# Sets player's direction to stalled
end_player_hit_mosquito:
	lw	$ra, 0($sp)
	addi	$sp, $sp, 4
	jr	$ra

.include "procs_board.asm"
