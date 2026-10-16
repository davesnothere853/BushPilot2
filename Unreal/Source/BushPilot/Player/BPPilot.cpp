#include "Player/BPPilot.h"
#include "Vehicles/BPVehicleBase.h"
#include "Camera/CameraComponent.h"
#include "Components/CapsuleComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/PlayerController.h"
#include "EngineUtils.h"
#include "Engine/Engine.h"

ABPPilot::ABPPilot()
{
	PrimaryActorTick.bCanEverTick = true;
	GetCapsuleComponent()->InitCapsuleSize(30.f, 90.f);          // 1.8 m tall
	Eyes = CreateDefaultSubobject<UCameraComponent>(TEXT("Eyes"));
	Eyes->SetupAttachment(GetCapsuleComponent());
	Eyes->SetRelativeLocation(FVector(5.f, 0.f, 72.f));            // eyes at ~1.65 m
	Eyes->bUsePawnControlRotation = true;
	GetCharacterMovement()->MaxWalkSpeed = 160.f;
	GetCharacterMovement()->JumpZVelocity = 380.f;
	GetCharacterMovement()->SetWalkableFloorAngle(50.f);
	bUseControllerRotationYaw = true;
}

void ABPPilot::Tick(float Dt)
{
	Super::Tick(Dt);
	APlayerController* PC = Cast<APlayerController>(GetController());
	if (!PC) return;
	const FRotator Yaw(0.f, PC->GetControlRotation().Yaw, 0.f);
	const float F = (PC->IsInputKeyDown(EKeys::W) ? 1.f : 0.f) - (PC->IsInputKeyDown(EKeys::S) ? 1.f : 0.f);
	const float R = (PC->IsInputKeyDown(EKeys::D) ? 1.f : 0.f) - (PC->IsInputKeyDown(EKeys::A) ? 1.f : 0.f);
	AddMovementInput(Yaw.Vector(), F);
	AddMovementInput(FRotationMatrix(Yaw).GetScaledAxis(EAxis::Y), R);
	GetCharacterMovement()->MaxWalkSpeed = PC->IsInputKeyDown(EKeys::LeftShift) ? 520.f : 160.f;
	float MX = 0.f, MY = 0.f;
	PC->GetInputMouseDelta(MX, MY);
	AddControllerYawInput(MX);
	AddControllerPitchInput(-MY);
	if (PC->WasInputKeyJustPressed(EKeys::SpaceBar)) Jump();
	// get in: the nearest vehicle within 5 m
	ABPVehicleBase* Best = nullptr;
	float BestD = 500.f;
	for (TActorIterator<ABPVehicleBase> It(GetWorld()); It; ++It)
	{
		const float D = FVector::Dist(It->GetActorLocation(), GetActorLocation());
		if (D < BestD) { BestD = D; Best = *It; }
	}
	if (GEngine)
	{
		GEngine->AddOnScreenDebugMessage(1, 0.f, FColor(255, 200, 120), Best ? FString::Printf(TEXT("F  get in the %s"), *Best->Title.ToLower()) : FString(TEXT("WASD walk  Shift run  Space jump")));
	}
	if (Best && PC->WasInputKeyJustPressed(EKeys::F))
	{
		Best->Driver = this;
		SetActorHiddenInGame(true);
		SetActorEnableCollision(false);
		PC->Possess(Best);
	}
}
