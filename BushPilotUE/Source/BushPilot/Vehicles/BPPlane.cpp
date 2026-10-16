#include "Vehicles/BPPlane.h"
#include "Components/BoxComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Camera/CameraComponent.h"
#include "GameFramework/SpringArmComponent.h"
#include "GameFramework/PlayerController.h"

static const float RHO = 1.2e-6f;            // air, kg/cm^3

ABPPlane::ABPPlane()
{
	Title = TEXT("BUSH PLANE");
	Body->SetBoxExtent(FVector(330.f, 45.f, 60.f));
	Body->SetMassOverrideInKg(NAME_None, 800.f, true);
	Body->SetCenterOfMass(FVector(20.f, 0.f, 10.f));
	Body->SetAngularDamping(0.05f);
	Body->SetLinearDamping(0.0f);
	const FLinearColor Red(0.55f, 0.05f, 0.04f), White(0.85f, 0.85f, 0.82f), Dark(0.04f, 0.04f, 0.04f), Glass(0.1f, 0.13f, 0.16f);
	// fuselage: nose at +X, the wing on top (high wing), tail low
	Part("Fuse", TEXT("Cube"), FVector(40, 0, 20), FVector(330, 76, 110), White);
	Part("Cowl", TEXT("Cube"), FVector(230, 0, 25), FVector(70, 74, 80), Red);
	Part("Boom", TEXT("Cube"), FVector(-260, 0, 35), FVector(330, 40, 50), White, FRotator(4, 0, 0));
	Part("Windows", TEXT("Cube"), FVector(110, 0, 62), FVector(90, 78, 34), Glass);
	Part("Wing", TEXT("Cube"), FVector(70, 0, 88), FVector(160, 1080, 14), Red);
	Part("Stab", TEXT("Cube"), FVector(-400, 0, 48), FVector(70, 300, 6), Red);
	Part("Fin", TEXT("Cube"), FVector(-405, 0, 100), FVector(80, 6, 110), Red);
	Part("StrutL", TEXT("Cube"), FVector(80, -250, 40), FVector(8, 8, 120), Dark, FRotator(0, 0, -62));
	Part("StrutR", TEXT("Cube"), FVector(80, 250, 40), FVector(8, 8, 120), Dark, FRotator(0, 0, 62));
	Part("GearL", TEXT("Cube"), FVector(160, -55, -55), FVector(6, 6, 70), Dark, FRotator(0, 0, -25));
	Part("GearR", TEXT("Cube"), FVector(160, 55, -55), FVector(6, 6, 70), Dark, FRotator(0, 0, 25));
	Prop = Part("Prop", TEXT("Cube"), FVector(272, 0, 25), FVector(4, 200, 14), Dark);
	SeatCam->SetRelativeLocation(FVector(100.f, 0.f, 70.f));
	Boom->TargetArmLength = 1300.f;
	Boom->SetRelativeLocation(FVector(0, 0, 150));
	// gear: big soft tundra tyres up front, a tailwheel
	FBPWheel W;
	W.Radius = 34.f; W.Width = 30.f; W.Rest = 18.f; W.K = 30000.f; W.C = 3500.f; W.Grip = 0.85f;
	W.Local = FVector(160, -85, -40); AddWheel(W, Dark);
	W.Local = FVector(160, 85, -40); AddWheel(W, Dark);
	W.Radius = 12.f; W.Width = 8.f; W.Rest = 14.f; W.K = 12000.f; W.C = 1500.f; W.bBrake = false; W.bSteer = true; W.SteerSign = -1.f; W.Grip = 0.6f;
	W.Local = FVector(-560, 0, 10); AddWheel(W, Dark);
	// the flight model's surfaces (areas in cm^2): wing 16.6 m^2 in two halves with a little dihedral
	const float Dih = FMath::DegreesToRadians(1.5f);
	Surf.Add({FVector(55, -270, 88), FVector(0, FMath::Sin(Dih), FMath::Cos(Dih)), FVector(0, 1, 0), 83000.f, 5.2f, 0.012f});
	Surf.Add({FVector(55, 270, 88), FVector(0, -FMath::Sin(Dih), FMath::Cos(Dih)), FVector(0, 1, 0), 83000.f, 5.2f, 0.012f});
	Surf.Add({FVector(-400, 0, 48), FVector(0, 0, 1), FVector(0, 1, 0), 22000.f, 4.0f, 0.01f, 0.f, 18.f});   // tailplane + elevator
	Surf.Add({FVector(-405, 0, 100), FVector(0, 1, 0), FVector(0, 0, 1), 9000.f, 3.5f, 0.01f, 0.f, 18.f});    // fin + rudder
	// the fuselage itself: a little side area so it weathervanes, mostly drag
	Surf.Add({FVector(-60, 0, 30), FVector(0, 1, 0), FVector(0, 0, 1), 14000.f, 1.0f, 0.05f, 0.f, 25.f});
}

void ABPPlane::Drive(float Dt, APlayerController* PC)
{
	if (PC)
	{
		if (Key(PC, EKeys::LeftShift)) Throttle = FMath::Min(1.f, Throttle + Dt * 0.6f);
		if (Key(PC, EKeys::LeftControl)) Throttle = FMath::Max(0.f, Throttle - Dt * 0.6f);
		const float P = (Key(PC, EKeys::S) || Key(PC, EKeys::Down) ? 1.f : 0.f) - (Key(PC, EKeys::W) || Key(PC, EKeys::Up) ? 1.f : 0.f);
		const float R = (Key(PC, EKeys::D) || Key(PC, EKeys::Right) ? 1.f : 0.f) - (Key(PC, EKeys::A) || Key(PC, EKeys::Left) ? 1.f : 0.f);
		const float Yw = (Key(PC, EKeys::E) ? 1.f : 0.f) - (Key(PC, EKeys::Q) ? 1.f : 0.f);
		Pitch = FMath::FInterpTo(Pitch, P, Dt, 5.f);
		Roll = FMath::FInterpTo(Roll, R, Dt, 5.f);
		Yaw = FMath::FInterpTo(Yaw, Yw, Dt, 5.f);
		if (Pressed(PC, EKeys::G)) Flaps = Flaps > 0.f ? 0.f : 1.f;
	}
	else
	{
		Throttle = 0.f;
	}
	const FTransform T = Body->GetComponentTransform();
	const FVector V = Body->GetPhysicsLinearVelocity();
	Ias = V.Size();
	// the propeller: full static thrust ~ 2.6 kN, falling with speed (power limited)
	const float Power = 180.f * 745.7f * 0.75f * 10000.f;
	const float Thrust = Throttle * FMath::Min(260000.f, Power / FMath::Max(Ias, 300.f));
	Body->AddForceAtLocation(T.GetUnitAxis(EAxis::X) * Thrust, T.TransformPosition(FVector(270, 0, 25)));
	// the controls, as extra angle on their surfaces (radians)
	const float D = FMath::DegreesToRadians(1.f);
	Surf[0].Control = Roll * 9.f * D + Flaps * 6.f * D;
	Surf[1].Control = -Roll * 9.f * D + Flaps * 6.f * D;
	Surf[2].Control = -Pitch * 18.f * D;
	Surf[3].Control = Yaw * 20.f * D;
	for (const FBPSurface& S : Surf)
	{
		const FVector P = T.TransformPosition(S.Pos);
		const FVector Va = -Body->GetPhysicsLinearVelocityAtPoint(P);       // the air meeting it
		const float Sp = Va.Size();
		if (Sp < 50.f) continue;
		const FVector N = T.TransformVectorNoScale(S.Normal);
		const FVector Fw = T.GetUnitAxis(EAxis::X);
		const FVector Dir = Va / Sp;
		// angle of attack: the surface moving through the air (Vm = -Va); air
		// meeting it from below (it sinks relative to its normal) is positive
		const FVector Vm = -Va;
		const float A = FMath::Atan2(-FVector::DotProduct(Vm, N), FVector::DotProduct(Vm, Fw)) + S.Control;
		const float Stall = FMath::DegreesToRadians(S.StallDeg);
		float Cl = S.Cla * A;
		if (FMath::Abs(A) > Stall)
		{
			// past the stall the lift falls away to a flat plate's
			const float Over = FMath::Clamp((FMath::Abs(A) - Stall) / FMath::DegreesToRadians(10.f), 0.f, 1.f);
			Cl = FMath::Sign(A) * FMath::Lerp(S.Cla * Stall, 0.9f * FMath::Sin(2.f * FMath::Abs(A)), Over);
		}
		const float Cd = S.Cd0 + 0.045f * Cl * Cl + 1.1f * FMath::Square(FMath::Sin(A)) * 0.5f;
		const float Q = 0.5f * RHO * Sp * Sp * S.Area;
		const FVector SpanW = T.TransformVectorNoScale(S.Span);
		FVector LiftDir = FVector::CrossProduct(Dir, SpanW).GetSafeNormal();
		if (FVector::DotProduct(LiftDir, N) < 0.f) LiftDir = -LiftDir;
		Body->AddForceAtLocation(LiftDir * Cl * Q + Dir * Cd * Q, P);
		if (&S == &Surf[0]) Aoa = FMath::RadiansToDegrees(A - S.Control);
	}
	// some rotational damping from the air (the surfaces give most of it)
	Body->AddTorqueInRadians(-Body->GetPhysicsAngularVelocityInRadians() * Ias * 4000.f);
	// gear: brakes on B, the tailwheel steers with the rudder
	const float Brake = PC && Key(PC, EKeys::B) ? 1.f : 0.f;
	for (FBPWheel& W : Wheels)
	{
		W.Steer = W.bSteer ? Yaw * FMath::DegreesToRadians(25.f) : 0.f;
		W.Step(Body, Dt, 0.f, Brake, 0.f);
	}
	PropDeg = FMath::Fmod(PropDeg + Dt * (300.f + 2400.f * Throttle) * 6.f, 360.f);
	if (Prop) Prop->SetRelativeRotation(FRotator(0.f, 0.f, PropDeg));
}

FString ABPPlane::Hud() const
{
	return FString::Printf(TEXT("throttle %d%%  AoA %.0f  flaps %s  alt %.0f m\nShift/Ctrl throttle  W/S pitch  A/D roll  Q/E rudder  B brakes  G flaps"),
		int32(Throttle * 100.f), Aoa, Flaps > 0.f ? TEXT("down") : TEXT("up"), GetActorLocation().Z / 100.f);
}
