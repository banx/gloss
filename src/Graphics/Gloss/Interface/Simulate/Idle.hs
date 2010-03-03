
module Graphics.Gloss.Interface.Simulate.Idle
	( callback_simulate_idle )
where
import Graphics.UI.GLUT						(($=), get)
import qualified Graphics.Gloss.Interface.ViewPort.State	as VP
import qualified Graphics.Gloss.Interface.Animate.State		as AN
import qualified Graphics.Gloss.Interface.Simulate.State	as SM
import qualified Graphics.UI.GLUT				as GLUT
import Data.IORef
import Control.Monad


-- | The graphics library calls back on this function when it's finished drawing
--	and it's time to do some computation.
callback_simulate_idle
	:: IORef SM.State				-- ^ the simulation state
	-> IORef AN.State				-- ^ the animation statea
	-> IORef VP.State				-- ^ the viewport state
	-> IORef world					-- ^ the current world
	-> world					-- ^ the initial world
	-> (VP.State -> Float -> world -> world) 	-- ^ fn to advance the world
	-> Float					-- ^ how much time to advance world by 
							--	in single step mode
	-> IO ()
	
callback_simulate_idle simSR animateSR viewSR worldSR worldStart worldAdvance singleStepTime
 = {-# SCC "callbackIdle" #-}
   do	simS		<- readIORef simSR
	let result
		| SM.stateReset simS
		= simulate_reset simSR worldSR worldStart

		| SM.stateRun   simS
		= simulate_run   simSR animateSR viewSR worldSR worldAdvance
		
		| SM.stateStep  simS
		= simulate_step  simSR viewSR worldSR worldAdvance singleStepTime
		
		| otherwise
		= return ()
		
	result
 

-- reset the world to 
simulate_reset simSR worldSR worldStart
 = do	writeIORef worldSR worldStart

 	simSR `modifyIORef` \c -> c 	
		{ SM.stateReset		= False 
	 	, SM.stateIteration	= 0 
		, SM.stateSimTime	= 0 }
	 
	GLUT.postRedisplay Nothing
	 
 
-- take the number of steps specified by controlWarp
simulate_run 
	:: IORef SM.State
	-> IORef AN.State
	-> IORef VP.State
	-> IORef world
	-> (VP.State -> Float -> world -> world)
	-> IO ()
	
simulate_run simSR animateSR viewSR worldSR worldAdvance
 = do	
	simS		<- readIORef simSR
	viewS		<- readIORef viewSR
	worldS		<- readIORef worldSR

	-- get the elapsed time since the start simulation (wall clock)
 	elapsedTime_msec	<- get GLUT.elapsedTime
	let elapsedTime		= fromIntegral elapsedTime_msec / 1000

	-- get how far along the simulation is
	simTime			<- simSR `getsIORef` SM.stateSimTime
 
 	-- we want to simulate this much extra time to bring the simulation
	--	up to the wall clock.
	let thisTime	= elapsedTime - simTime
	 
	-- work out how many steps of simulation this equals
	resolution	<- simSR `getsIORef` SM.stateResolution
	let timePerStep	= 1 / fromIntegral resolution
	let thisSteps_	= truncate $ fromIntegral resolution * thisTime
	let thisSteps	= if thisSteps_ < 0 then 0 else thisSteps_

	let newSimTime	= simTime + fromIntegral thisSteps * timePerStep
	 
{-	putStr	$  "elapsed time    = " ++ show elapsedTime 	++ "\n"
		++ "sim time        = " ++ show simTime		++ "\n"
		++ "this time       = " ++ show thisTime	++ "\n"
		++ "this steps      = " ++ show thisSteps	++ "\n"
		++ "new sim time    = " ++ show newSimTime	++ "\n"
		++ "taking          = " ++ show thisSteps	++ "\n\n"
-}
 	-- work out the final step number for this display cycle
	let nStart	= SM.stateIteration simS
	let nFinal 	= nStart + thisSteps

	-- keep advancing the world until we get to the final iteration number
	let (_, world')	= 
		until 	(\(n, w) 	-> n >= nFinal)
			(\(n, w)	-> (n+1, worldAdvance viewS timePerStep w))
			(nStart, worldS)
	
	-- write the world back into its IORef
	writeIORef worldSR world'

	-- update the control state
	simSR `modifyIORef` \c -> c
		{ SM.stateIteration	= nFinal
		, SM.stateSimTime	= newSimTime 
		, SM.stateStepsPerFrame	= fromIntegral thisSteps }
	
	-- tell glut we want to draw the window after returning
	GLUT.postRedisplay Nothing


-- take a single step
simulate_step 
	:: IORef SM.State
	-> IORef VP.State
	-> IORef world
	-> (VP.State -> Float -> world -> world) 
	-> Float
	-> IO ()

simulate_step simSR viewSR worldSR worldAdvance singleStepTime
 = do
	simS		<- readIORef simSR
	viewS		<- readIORef viewSR
	
 	world		<- readIORef worldSR
	let world'	= worldAdvance viewS singleStepTime world
	
	writeIORef worldSR world'
	simSR `modifyIORef` \c -> c 	
		{ SM.stateIteration 	= SM.stateIteration c + 1 
	 	, SM.stateStep		= False }
	 
	GLUT.postRedisplay Nothing


getsIORef ref fun
 = liftM fun $ readIORef ref