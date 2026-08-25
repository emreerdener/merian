export function speciesDictionaryRefusalAnswer(reason: string): string {
  switch (reason) {
    case "foraging_or_ingestion":
      return "I cannot tell you that this species is safe to eat, brew, cook, or feed to people or animals. Treat Species Dictionary information as educational only, and consult a qualified local expert before any ingestion-related decision. I can still explain traits, habitat, seasonality, or lookalikes from this Species Dictionary page.";
    case "medical_or_veterinary":
      return "I cannot provide medical, veterinary, poison-control, dosage, or treatment advice. If there is possible exposure, a bite or sting, ingestion, or a concerning reaction, contact local emergency services, poison control, or a qualified clinician. I can explain hazard classifications from this Species Dictionary page in non-treatment terms.";
    case "dangerous_handling":
      return "I cannot give instructions for dangerous handling, capture, killing, poisoning, or removal. Observe wildlife from a safe distance and follow local guidance. I can describe traits, habitat, or lookalikes from this Species Dictionary page.";
    case "legal_or_collection":
      return "I cannot determine whether collection, harvest, capture, or removal is legal. Rules vary by location, land manager, and species status. Check local regulations or a qualified authority before acting. I can summarize the conservation and taxonomy information on this Species Dictionary page.";
    default:
      return "I cannot help with that request, but I can answer educational questions about traits, habitat, seasonality, taxonomy, or lookalikes from this Species Dictionary page.";
  }
}
