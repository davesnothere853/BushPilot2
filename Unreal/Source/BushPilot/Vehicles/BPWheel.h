#pragma once
#include "CoreMinimal.h"

class UPrimitiveComponent;
class UStaticMeshComponent;

/**
 * A raycast wheel (made for the Unreal build: our own tyre and suspension, so
 * mud, gravel and soft ground can come in later). Unreal units: cm, kg, s.
 * The spring and damper numbers are the same as N/m and N.s/m.
 */
struct FBPWheel
{
	FVector Local = FVector::ZeroVector;   // suspension top, in the body's frame (cm)
	float Radius = 38.f;                   // cm
	float Width = 24.f;                    // cm (looks)
	float Rest = 30.f;                     // suspension travel at rest length (cm)
	float K = 36000.f;                     // spring
	float C = 5000.f;                      // damper
	float Grip = 1.0f;                     // tyre friction coefficient on firm ground
	bool bDrive = false;
	bool bSteer = false;
	bool bBrake = true;
	bool bHandbrake = false;
	float SteerSign = 1.f;                 // tailwheels steer the other way

	// state
	float Steer = 0.f;                     // radians
	float Comp = 0.f;                      // compression (cm)
	float SpinDeg = 0.f;
	bool bContact = false;
	float Load = 0.f;                      // last suspension force
	UStaticMeshComponent* Mesh = nullptr;

	/** Steps the wheel: suspension, tyre forces (drive, brake, side grip) on Body. */
	void Step(UPrimitiveComponent* Body, float Dt, float DriveForce, float Brake, float Handbrake);
};
