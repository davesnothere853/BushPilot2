#pragma once
#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "BPMudComponent.generated.h"

/** Mud on the ground (DESIGN: "better driving and mud physics than SnowRunner").
 *  The world's mud field: depth, wetness and stickiness by place; tyre ruts that
 *  stay and deepen, fill with water, and change the next pass. Wheels ask it
 *  how much they sink and how much grip and drag they get. First version: the
 *  data and the queries; the deformation mesh and the visuals come next. */
UCLASS(ClassGroup = (BushPilot), meta = (BlueprintSpawnableComponent))
class BUSHPILOT_API UBPMudComponent : public UActorComponent
{
	GENERATED_BODY()
public:
	UBPMudComponent();

	/** Size of the mud field (m) and its resolution (m per cell). */
	UPROPERTY(EditAnywhere, Category = "Mud") FVector2D FieldOrigin = FVector2D(-120.f, -320.f);
	UPROPERTY(EditAnywhere, Category = "Mud") FVector2D FieldSize = FVector2D(880.f, 640.f);
	UPROPERTY(EditAnywhere, Category = "Mud") float CellSize = 0.25f;
	/** 0 dry .. 1 soaked: rain raises it, sun and wind dry it out. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Mud") float Wetness = 0.7f;

	/** How far a tyre of this contact pressure (kPa) sinks at a world point (cm), and the
	 *  rolling drag (0..1 of load) and grip multiplier it gets there. */
	UFUNCTION(BlueprintCallable, Category = "Mud")
	void Query(const FVector& WorldPos, float PressureKPa, float& OutSinkCm, float& OutDrag, float& OutGrip) const;

	/** A tyre rolled or spun over this point: deepen the rut (spin digs more). */
	UFUNCTION(BlueprintCallable, Category = "Mud")
	void Churn(const FVector& WorldPos, float WidthM, float SinkCm, float SlipRatio);

	/** Rut depth (cm) at a point - for the ground deformation and visuals. */
	UFUNCTION(BlueprintCallable, Category = "Mud")
	float RutDepth(const FVector& WorldPos) const;

private:
	int32 NX = 0, NY = 0;
	TArray<float> Depth;   // mud thickness over firm ground (cm), by cell
	TArray<float> Rut;     // rut depth worn in (cm), by cell
	bool Cell(const FVector& WorldPos, int32& OutI, int32& OutJ) const;
	virtual void BeginPlay() override;
};
