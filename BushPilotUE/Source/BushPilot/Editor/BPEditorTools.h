#pragma once

#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "BPEditorTools.generated.h"

class ALandscape;
class UMaterialInterface;

/** Editor helpers the build scripts call from Python (unreal.BPEditorTools). */
UCLASS()
class BUSHPILOT_API UBPEditorTools : public UBlueprintFunctionLibrary
{
	GENERATED_BODY()
public:
	/**
	 * Builds a Landscape from a raw 16-bit heightmap (little-endian, Size x Size,
	 * 32768 = Origin.Z). CellCm = metres between samples * 100. ZScale is the
	 * landscape's Z scale (100 -> +-256 m range, 1/128 cm per unit * ZScale).
	 * Size must be (components * 63) + 1, e.g. 1009 or 2017.
	 */
	UFUNCTION(BlueprintCallable, Category = "BushPilot|Editor", meta = (WorldContext = "WorldContext"))
	static ALandscape* BuildLandscapeFromR16(UObject* WorldContext, const FString& Path, int32 Size, float CellCm, float ZScale,
		FVector Origin, UMaterialInterface* Material, const FString& Label);

	/** Sets a landscape's material after it was built. */
	UFUNCTION(BlueprintCallable, Category = "BushPilot|Editor")
	static void SetLandscapeMaterial(ALandscape* Landscape, UMaterialInterface* Material);
};
