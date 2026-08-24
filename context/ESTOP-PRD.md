# E-stop module

## Problem

A fallen G1 keeps receiving commands because dimos does not detect the fall or stop its control tasks.

## Goal

Add an e-stop module that stops the robot when it tilts too far or when an operator sends a stop message, then keeps it stopped until the process restarts.

## Done when

The G1 stops during both deliberate fall tests and does not stop during a 10 minute standing test.

Tech spec: https://github.com/dimensionalOS/dimos/issues/3621
