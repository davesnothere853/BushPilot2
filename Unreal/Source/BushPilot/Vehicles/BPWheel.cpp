#include "Vehicles/BPWheel.h"
#include "Components/PrimitiveComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/World.h"

void FBPWheel::Step(UPrimitiveComponent* Body, float Dt, float DriveForce, float Brake, float Handbrake)
{
	if (!Body || Dt <= 0.f)
	{
		return;
	}
	const FTransform T = Body->GetComponentTransform();
	const FVector Up = T.GetUnitAxis(EAxis::Z);
	const FVector Top = T.TransformPosition(Local);
	const float Reach = Rest + Radius;
	FHitResult Hit;
	FCollisionQueryParams Q(SCENE_QUERY_STAT(BPWheel), false, Body->GetOwner());
	bContact = Body->GetWorld()->LineTraceSingleByChannel(Hit, Top, Top - Up * Reach, ECC_Visibility, Q);
	float Dist = Reach;
	if (bContact)
	{
		Dist = Hit.Distance;
		const float NewComp = Reach - Dist;
		const float CompVel = (NewComp - Comp) / Dt;
		Comp = NewComp;
		Load = FMath::Max(0.f, K * Comp + C * CompVel);
		const FVector P = Hit.ImpactPoint;
		const FVector N = Hit.ImpactNormal;
		Body->AddForceAtLocation(Up * Load, P);

		// the tyre: its heading on the ground plane
		const FVector BodyFwd = T.GetUnitAxis(EAxis::X);
		const FVector Fwd0 = BodyFwd.RotateAngleAxis(FMath::RadiansToDegrees(Steer * SteerSign), Up);
		const FVector Fwd = (Fwd0 - N * FVector::DotProduct(Fwd0, N)).GetSafeNormal();
		const FVector Side = FVector::CrossProduct(N, Fwd).GetSafeNormal();
		const FVector V = Body->GetPhysicsLinearVelocityAtPoint(P);
		const float VLong = FVector::DotProduct(V, Fwd);
		const float VLat = FVector::DotProduct(V, Side);
		const float MaxF = Grip * Load;

		float FLong = bDrive ? DriveForce : 0.f;
		// rolling resistance
		FLong -= FMath::Clamp(VLong * 0.5f, -1.f, 1.f) * 0.015f * Load;
		// brakes (and the handbrake on the wheels that have it)
		const float B = FMath::Clamp((bBrake ? Brake : 0.f) + (bHandbrake ? Handbrake : 0.f), 0.f, 1.f);
		if (B > 0.f)
		{
			FLong -= FMath::Clamp(VLong / 50.f, -1.f, 1.f) * B * MaxF * 0.95f;
		}
		// side grip: resists sliding, saturating (a slide when it's past grip)
		float FLat = -FMath::Clamp(VLat / 120.f, -1.f, 1.f) * MaxF;
		if (bHandbrake && Handbrake > 0.5f)
		{
			FLat *= 0.45f;
		}
		// the friction circle
		const float FT = FMath::Sqrt(FLong * FLong + FLat * FLat);
		if (FT > MaxF && FT > 1.f)
		{
			FLong *= MaxF / FT;
			FLat *= MaxF / FT;
		}
		Body->AddForceAtLocation(Fwd * FLong + Side * FLat, P);
		SpinDeg += FMath::RadiansToDegrees(VLong / Radius * Dt) * ((B > 0.9f && FMath::Abs(VLong) < 30.f) ? 0.f : 1.f);
	}
	else
	{
		Comp = 0.f;
		Load = 0.f;
	}
	if (Mesh)
	{
		const FVector Centre = Local - FVector(0, 0, Dist - Radius);
		Mesh->SetRelativeLocation(Centre);
		// cylinder: axis along Z; lay it on its side (axis along Y), steer about Z, spin about Y
		const FRotator Lay(0.f, 0.f, 90.f);
		const FQuat SteerQ(FVector::UpVector, Steer * SteerSign);
		const FQuat SpinQ(FVector::RightVector, FMath::DegreesToRadians(-SpinDeg));
		Mesh->SetRelativeRotation(SteerQ * SpinQ * Lay.Quaternion());
	}
}
