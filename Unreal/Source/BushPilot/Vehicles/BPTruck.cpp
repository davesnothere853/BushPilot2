#include "Vehicles/BPTruck.h"
#include "Components/BoxComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Camera/CameraComponent.h"
#include "GameFramework/SpringArmComponent.h"
#include "GameFramework/PlayerController.h"

ABPTruck::ABPTruck()
{
	Title = TEXT("PICKUP");
	Body->SetBoxExtent(FVector(250.f, 95.f, 45.f));       // the frame and cab volume (5.0 x 1.9 m)
	Body->SetMassOverrideInKg(NAME_None, 1900.f, true);
	Body->SetCenterOfMass(FVector(10.f, 0.f, -25.f));
	const FLinearColor Paint(0.42f, 0.08f, 0.05f), Dark(0.05f, 0.05f, 0.05f), Chrome(0.6f, 0.6f, 0.62f), Glass(0.08f, 0.1f, 0.12f), Tyre(0.03f, 0.03f, 0.03f);
	// body (simple shapes, real proportions of an '80s full-size pickup)
	Part("Bed", TEXT("Cube"), FVector(-150, 0, 40), FVector(230, 190, 55), Paint);
	Part("BedFloor", TEXT("Cube"), FVector(-150, 0, 14), FVector(226, 186, 4), Dark);
	Part("Cab", TEXT("Cube"), FVector(15, 0, 70), FVector(130, 190, 110), Paint);
	Part("Windshield", TEXT("Cube"), FVector(82, 0, 95), FVector(6, 170, 55), Glass, FRotator(-30, 0, 0));
	Part("Hood", TEXT("Cube"), FVector(160, 0, 45), FVector(170, 186, 50), Paint);
	Part("Grille", TEXT("Cube"), FVector(247, 0, 40), FVector(6, 170, 40), Chrome);
	Part("Bumper", TEXT("Cube"), FVector(258, 0, 12), FVector(14, 200, 16), Chrome);
	Part("BumperR", TEXT("Cube"), FVector(-268, 0, 12), FVector(12, 196, 14), Chrome);
	Part("Frame", TEXT("Cube"), FVector(0, 0, -5), FVector(500, 90, 20), Dark);
	SeatCam->SetRelativeLocation(FVector(-5.f, -40.f, 120.f));
	Boom->TargetArmLength = 800.f;
	Boom->SetRelativeLocation(FVector(0, 0, 120));
	// wheels: 31" tyres, 3.3 m wheelbase, 1.65 m track
	FBPWheel W;
	W.Radius = 39.f; W.Width = 26.f; W.Rest = 26.f; W.K = 52000.f; W.C = 7000.f; W.Grip = 1.0f;
	W.bDrive = true;
	W.bSteer = true;
	W.Local = FVector(165, -82, 0); AddWheel(W, Tyre);
	W.Local = FVector(165, 82, 0); AddWheel(W, Tyre);
	W.bSteer = false; W.bHandbrake = true;
	W.Local = FVector(-165, -82, 0); AddWheel(W, Tyre);
	W.Local = FVector(-165, 82, 0); AddWheel(W, Tyre);
}

void ABPTruck::BeginPlay()
{
	Super::BeginPlay();
}

void ABPTruck::Drive(float Dt, APlayerController* PC)
{
	const FVector V = Body->GetPhysicsLinearVelocity();
	const float Fwd = FVector::DotProduct(V, GetActorForwardVector());     // cm/s
	float Want = 0.f, Brake = 0.f, Hand = 0.f, St = 0.f;
	if (PC)
	{
		const bool Up = Key(PC, EKeys::W) || Key(PC, EKeys::Up);
		const bool Dn = Key(PC, EKeys::S) || Key(PC, EKeys::Down);
		St = (Key(PC, EKeys::D) || Key(PC, EKeys::Right) ? 1.f : 0.f) - (Key(PC, EKeys::A) || Key(PC, EKeys::Left) ? 1.f : 0.f);
		Hand = Key(PC, EKeys::SpaceBar) ? 1.f : 0.f;
		if (!bReverse)
		{
			Want = Up ? 1.f : 0.f;
			if (Dn) { if (Fwd > 80.f) Brake = 1.f; else bReverse = true; }
		}
		else
		{
			Want = Dn ? -0.6f : 0.f;
			if (Up) { if (Fwd < -80.f) Brake = 1.f; else bReverse = false; }
		}
	}
	else
	{
		Brake = 0.3f; Hand = 1.f;
	}
	Throttle = FMath::FInterpTo(Throttle, Want, Dt, 4.f);
	// steering: slower and less at speed
	const float MaxSteer = FMath::DegreesToRadians(FMath::Lerp(34.f, 8.f, FMath::Clamp(FMath::Abs(Fwd) / 2500.f, 0.f, 1.f)));
	SteerIn = FMath::FInterpTo(SteerIn, St, Dt, 3.f);
	// engine: ~ 190 hp; force at the tyres limited by grip at low speed and power higher up
	const float Speed = FMath::Max(FMath::Abs(Fwd), 150.f);
	const float Power = 140000.f * 10000.f;                  // W -> kg cm^2/s^3
	const float MaxForce = 1900.f * 980.f * 0.9f;            // what four tyres can push
	const float F = Throttle >= 0.f ? FMath::Min(MaxForce, Power / Speed) * Throttle : FMath::Min(MaxForce * 0.6f, Power / Speed) * Throttle;
	Gear = FMath::Clamp(1 + int32(FMath::Abs(Fwd) / 700.f), 1, 4);
	int32 Driven = 0;
	for (FBPWheel& W : Wheels) if (W.bDrive) Driven++;
	for (FBPWheel& W : Wheels)
	{
		W.Steer = W.bSteer ? SteerIn * MaxSteer : 0.f;
		W.Step(Body, Dt, Driven > 0 ? F / Driven : 0.f, Brake, Hand);
	}
	// air: half a ton of drag at highway speed
	Body->AddForce(-V * V.Size() * 0.016f);
}

FString ABPTruck::Hud() const
{
	return FString::Printf(TEXT("%s  gear %d   W/S gas-brake  A/D steer  Space handbrake"), bReverse ? TEXT("R") : TEXT("D"), Gear);
}
