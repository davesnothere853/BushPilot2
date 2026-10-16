#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Pawn.h"
#include "Vehicles/BPWheel.h"
#include "BPVehicleBase.generated.h"

class UBoxComponent;
class UStaticMeshComponent;
class USpringArmComponent;
class UCameraComponent;
class UMaterialInstanceDynamic;

/**
 * Base for the test-bed vehicles (Unreal build, new code): a physics body,
 * raycast wheels, parts built from simple shapes (placeholders until the real
 * models), a chase camera and a seat camera, getting in and out on F.
 * Keys are read straight off the player controller each frame.
 */
UCLASS(Abstract)
class BUSHPILOT_API ABPVehicleBase : public APawn
{
	GENERATED_BODY()
public:
	ABPVehicleBase();
	virtual void Tick(float Dt) override;
	virtual void PossessedBy(AController* NewController) override;
	virtual void UnPossessed() override;

	UPROPERTY(VisibleAnywhere, Category = "Vehicle") UBoxComponent* Body;
	UPROPERTY(VisibleAnywhere, Category = "Vehicle") USpringArmComponent* Boom;
	UPROPERTY(VisibleAnywhere, Category = "Vehicle") UCameraComponent* ChaseCam;
	UPROPERTY(VisibleAnywhere, Category = "Vehicle") UCameraComponent* SeatCam;

	/** Who got in (put back out on F). */
	UPROPERTY() APawn* Driver = nullptr;
	/** Shown in the corner. */
	FString Title = TEXT("Vehicle");

protected:
	TArray<FBPWheel> Wheels;
	UStaticMeshComponent* Part(const FName& Name, const TCHAR* Shape, const FVector& Pos, const FVector& SizeCm, const FLinearColor& Color, const FRotator& Rot = FRotator::ZeroRotator);
	void AddWheel(const FBPWheel& W, const FLinearColor& Color);
	/** Each vehicle's own driving / flying. */
	virtual void Drive(float Dt, class APlayerController* PC) {}
	virtual FString Hud() const { return FString(); }
	bool Key(class APlayerController* PC, const FKey& K) const;
	bool Pressed(class APlayerController* PC, const FKey& K) const;
	void GetOut();
	float SpeedKmh() const;

	UPROPERTY() TArray<UMaterialInstanceDynamic*> Mats;
	void ColorParts();
	float InTime = 0.f;
	bool bSeatView = false;
	float Look = 0.f, LookUp = 0.f;
};
