#include "Editor/BPEditorTools.h"
#include "BushPilot.h"
#include "Landscape.h"
#include "LandscapeInfo.h"
#include "LandscapeProxy.h"
#include "Materials/MaterialInterface.h"
#include "Misc/FileHelper.h"
#include "Engine/World.h"

ALandscape* UBPEditorTools::BuildLandscapeFromR16(UObject* WorldContext, const FString& Path, int32 Size, float CellCm, float ZScale,
	FVector Origin, UMaterialInterface* Material, const FString& Label)
{
#if WITH_EDITOR
	UWorld* World = WorldContext ? WorldContext->GetWorld() : nullptr;
	if (!World)
	{
		UE_LOG(LogBushPilot, Error, TEXT("BuildLandscape: no world"));
		return nullptr;
	}
	TArray<uint8> Bytes;
	if (!FFileHelper::LoadFileToArray(Bytes, *Path) || Bytes.Num() != Size * Size * 2)
	{
		UE_LOG(LogBushPilot, Error, TEXT("BuildLandscape: %s missing or wrong size (%d bytes, want %d)"), *Path, Bytes.Num(), Size * Size * 2);
		return nullptr;
	}
	const int32 QuadsPerSection = 63;
	if ((Size - 1) % QuadsPerSection != 0)
	{
		UE_LOG(LogBushPilot, Error, TEXT("BuildLandscape: size %d is not n*63+1"), Size);
		return nullptr;
	}
	TArray<uint16> Heights;
	Heights.SetNumUninitialized(Size * Size);
	FMemory::Memcpy(Heights.GetData(), Bytes.GetData(), Bytes.Num());

	// the actor sits at the corner; centre the grid on Origin
	const float Half = (Size - 1) * CellCm * 0.5f;
	const FVector Corner(Origin.X - Half, Origin.Y - Half, Origin.Z);
	FActorSpawnParameters Params;
	ALandscape* Landscape = World->SpawnActor<ALandscape>(Corner, FRotator::ZeroRotator, Params);
	if (!Landscape)
	{
		return nullptr;
	}
	Landscape->SetActorScale3D(FVector(CellCm, CellCm, ZScale));
	if (Material)
	{
		Landscape->LandscapeMaterial = Material;
	}

	TMap<FGuid, TArray<uint16>> HeightData;
	HeightData.Add(FGuid(), MoveTemp(Heights));
	TMap<FGuid, TArray<FLandscapeImportLayerInfo>> LayerInfos;
	LayerInfos.Add(FGuid(), TArray<FLandscapeImportLayerInfo>());

	Landscape->Import(FGuid::NewGuid(), 0, 0, Size - 1, Size - 1, 1, QuadsPerSection, HeightData, nullptr, LayerInfos,
		ELandscapeImportAlphamapType::Additive, TArrayView<const FLandscapeLayer>());

	ULandscapeInfo* Info = Landscape->GetLandscapeInfo();
	if (Info)
	{
		Info->UpdateLayerInfoMap(Landscape);
	}
	if (!Label.IsEmpty())
	{
		Landscape->SetActorLabel(Label);
	}
	Landscape->RegisterAllComponents();
	Landscape->PostEditChange();
	UE_LOG(LogBushPilot, Log, TEXT("BuildLandscape: %s %dx%d built"), *Label, Size, Size);
	return Landscape;
#else
	return nullptr;
#endif
}

void UBPEditorTools::SetLandscapeMaterial(ALandscape* Landscape, UMaterialInterface* Material)
{
#if WITH_EDITOR
	if (Landscape)
	{
		Landscape->LandscapeMaterial = Material;
		Landscape->PostEditChange();
	}
#endif
}
