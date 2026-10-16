#include "Vehicles/BPVehicleBase.h"
#include "BushPilot.h"
#include "Components/BoxComponent.h"
#include "Components/StaticMeshComponent.h"
#include "GameFramework/SpringArmComponent.h"
#include "Camera/CameraComponent.h"
#include "GameFramework/PlayerController.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Engine/StaticMesh.h"
#include "Engine/Engine.h"
#include "UObject/ConstructorHelpers.h"

static UStaticMesh* BPShape(const TCHAR* Name)
{
	return LoadObject<UStaticMesh>(nullptr, *FString::Printf(TEXT("/Engine/BasicShapes/%s.%s"), Name, Name));
}

ABPVehicleBase::ABPVehicleBase()
{
	PrimaryActorTick.bCanEverTick = true;
	Body = CreateDefaultSubobject<UBoxComponent>(TEXT("Body"));
	Body->SetSimulatePhysics(true);
	Body->SetCollisionProfileName(TEXT("PhysicsActor"));
	Body->SetBoxExtent(FVector(200, 90, 60));
	Body->SetLinearDamping(0.02f);
	Body->SetAngularDamping(0.3f);
	Body->BodyInstance.bUseCCD = true;
	RootComponent = Body;
	Boom = CreateDefaultSubobject<USpringArmComponent>(TEXT("Boom"));
	Boom->SetupAttachment(Body);
	Boom->TargetArmLength = 900.f;
	Boom->SetRelativeRotation(FRotator(-12.f, 0.f, 0.f));
	Boom->bEnableCameraLag = true;
	Boom->CameraLagSpeed = 6.f;
	Boom->bInheritPitch = false;
	Boom->bInheritRoll = false;
	Boom->bDoCollisionTest = true;
	ChaseCam = CreateDefaultSubobject<UCameraComponent>(TEXT("ChaseCam"));
	ChaseCam->SetupAttachment(Boom);
	SeatCam = CreateDefaultSubobject<UCameraComponent>(TEXT("SeatCam"));
	SeatCam->SetupAttachment(Body);
	SeatCam->SetAutoActivate(false);
	AutoPossessPlayer = EAutoReceiveInput::Disabled;
}

UStaticMeshComponent* ABPVehicleBase::Part(const FName& Name, const TCHAR* Shape, const FVector& Pos, const FVector& SizeCm, const FLinearColor& Color, const FRotator& Rot)
{
	UStaticMeshComponent* M = CreateDefaultSubobject<UStaticMeshComponent>(Name);
	M->SetupAttachment(Body);
	if (UStaticMesh* SM = BPShape(Shape))
	{
		M->SetStaticMesh(SM);
	}
	M->SetRelativeLocation(Pos);
	M->SetRelativeRotation(Rot);
	M->SetRelativeScale3D(SizeCm / 100.f);
	M->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	M->ComponentTags.Add(FName(*Color.ToString()));
	return M;
}

void ABPVehicleBase::AddWheel(const FBPWheel& W, const FLinearColor& Color)
{
	FBPWheel X = W;
	const int32 I = Wheels.Num();
	X.Mesh = Part(*FString::Printf(TEXT("Wheel%d"), I), TEXT("Cylinder"), W.Local, FVector(W.Radius * 2.f, W.Radius * 2.f, W.Width), Color);
	Wheels.Add(X);
}

bool ABPVehicleBase::Key(APlayerController* PC, const FKey& K) const { return PC && PC->IsInputKeyDown(K); }
bool ABPVehicleBase::Pressed(APlayerController* PC, const FKey& K) const { return PC && PC->WasInputKeyJustPressed(K); }

float ABPVehicleBase::SpeedKmh() const { return Body ? Body->GetPhysicsLinearVelocity().Size() * 0.036f : 0.f; }

void ABPVehicleBase::PossessedBy(AController* NewController)
{
	Super::PossessedBy(NewController);
	InTime = GetWorld() ? GetWorld()->GetTimeSeconds() : 0.f;
	ColorParts();
}

void ABPVehicleBase::ColorParts()
{
	// colour the parts once (the tag carries the colour)
	if (Mats.Num() == 0)
	{
		TArray<UStaticMeshComponent*> Comps;
		GetComponents(Comps);
		for (UStaticMeshComponent* M : Comps)
		{
			if (M->ComponentTags.Num() == 0) continue;
			FLinearColor C;
			C.InitFromString(M->ComponentTags[0].ToString());
			if (UMaterialInstanceDynamic* D = M->CreateDynamicMaterialInstance(0))
			{
				D->SetVectorParameterValue(TEXT("Color"), C);
				Mats.Add(D);
			}
		}
	}
}

void ABPVehicleBase::UnPossessed()
{
	Super::UnPossessed();
}

void ABPVehicleBase::GetOut()
{
	APlayerController* PC = Cast<APlayerController>(GetController());
	if (!PC || !Driver) return;
	const FVector Out = GetActorLocation() + GetActorRightVector() * -260.f + FVector(0, 0, 120.f);
	Driver->SetActorLocation(Out, false, nullptr, ETeleportType::TeleportPhysics);
	Driver->SetActorHiddenInGame(false);
	Driver->SetActorEnableCollision(true);
	PC->Possess(Driver);
	Driver = nullptr;
}

void ABPVehicleBase::Tick(float Dt)
{
	Super::Tick(Dt);
	if (!HasActorBegunPlay()) return;
	// colour the parts even before anyone gets in
	if (Mats.Num() == 0) ColorParts();
	APlayerController* PC = Cast<APlayerController>(GetController());
	if (PC)
	{
		if (Pressed(PC, EKeys::F) && GetWorld()->GetTimeSeconds() - InTime > 0.4f) { GetOut(); return; }
		if (Pressed(PC, EKeys::C))
		{
			bSeatView = !bSeatView;
			ChaseCam->SetActive(!bSeatView);
			SeatCam->SetActive(bSeatView);
		}
		float MX = 0.f, MY = 0.f;
		PC->GetInputMouseDelta(MX, MY);
		Look = FMath::Clamp(Look + MX * 2.f, -150.f, 150.f);
		LookUp = FMath::Clamp(LookUp + MY * 2.f, -60.f, 50.f);
		if (!Key(PC, EKeys::RightMouseButton) && !bSeatView)
		{
			Look = FMath::FInterpTo(Look, 0.f, Dt, 1.5f);
			LookUp = FMath::FInterpTo(LookUp, 0.f, Dt, 1.5f);
		}
		Boom->SetRelativeRotation(FRotator(-12.f + LookUp, Look, 0.f));
		SeatCam->SetRelativeRotation(FRotator(LookUp, Look, 0.f));
	}
	Drive(Dt, PC);
	if (PC && GEngine)
	{
		GEngine->AddOnScreenDebugMessage(1, 0.f, FColor(255, 200, 120),
			FString::Printf(TEXT("%s   %.0f km/h   %s\nF get out   C seat/chase view   right mouse: look"), *Title, SpeedKmh(), *Hud()));
	}
}
