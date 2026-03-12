import SwiftUI

struct InsightCarouselView: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    var body: some View {
        let refUrls: [String] = inferenceEngine.speciesData?.referenceImageUrl?.components(separatedBy: ",") ?? []
        let hasReferenceImage = !refUrls.isEmpty
        let hasUserImage = inferenceEngine.activePayload != nil || !inferenceEngine.activePayloads.isEmpty
        
        let totalImages = (inferenceEngine.activePayload != nil ? 1 : 0) + inferenceEngine.activePayloads.count + refUrls.count
        
        if totalImages > 0 {
            TabView {
                // Priority: Live Capture actively evaluated (Data payload)
                if let livePayload = inferenceEngine.activePayload, let uiImage = UIImage(data: livePayload) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .aspectRatio(1.0, contentMode: .fill)
                        .clipped()
                        .tag("user_image_live")
                        .id(livePayload.hashValue)
                }
                
                // User's Uploaded Images (Historic Pipeline deferred by path cleanly preventing OOMs natively)
                ForEach(Array(inferenceEngine.activePayloads.enumerated()), id: \.element) { index, path in
                    AsyncLocalImageView(imagePath: path)
                        .tag("user_image_\(index)")
                }
                
                // Tab 1+: Wikipedia / GBIF Reference Images
                ForEach(Array(refUrls.enumerated()), id: \.element) { index, urlString in
                    if let refUrl = URL(string: urlString) {
                        AsyncImage(url: refUrl, transaction: Transaction(animation: .easeInOut(duration: 0.3))) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .aspectRatio(1.0, contentMode: .fill)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white.opacity(0.1))
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .aspectRatio(1.0, contentMode: .fill)
                                    .clipped()
                                    .transition(.opacity)
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray.opacity(0.5))
                                    .aspectRatio(1.0, contentMode: .fill)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white.opacity(0.1))
                                    .transition(.opacity)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .tag("ref_\(index)")
                    }
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: totalImages > 1 ? .always : .never))
            .aspectRatio(1.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }
}

struct InsightToxicityBanner: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    private var isPoisonous: Bool {
        inferenceEngine.speciesData?.insightData.isPoisonous ?? false
    }
    
    var body: some View {
        if isPoisonous {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                VStack(alignment: .leading) {
                    Text("DANGER: TOXIC")
                        .font(.headline)
                    Text("This subject is known to be poisonous.")
                        .font(.subheadline)
                }
                Spacer()
                
                Button(action: {
                    print("Contact Local Experts Triggered")
                }) {
                    Text("Contact")
                        .fontWeight(.bold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .foregroundColor(.red)
                        .cornerRadius(8)
                }
                // Accessibility: Clear interactive routing
                .accessibilityHint("Double tap to contact local poison control experts.")
            }
            .padding()
            .background(Color.red.opacity(0.9))
            .foregroundColor(.white)
            .cornerRadius(12)
            // Accessibility: Explicitly anchor screen readers to the threat first
            .accessibilityAddTraits(.isHeader)
        } else {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.gray)
                    .padding(.top, 2)
                Text("Edibility Unknown. Merian is an educational tool. Never ingest wild flora.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

struct InsightTaxonomyHeader: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    private var commonName: String {
        inferenceEngine.speciesData?.commonName ?? "Scanning Subject..."
    }
    private var scientificName: String {
        inferenceEngine.speciesData?.scientificName ?? "Awaiting Taxonomy"
    }
    private var isPoisonous: Bool {
        inferenceEngine.speciesData?.insightData.isPoisonous ?? false
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(commonName)
                .font(.largeTitle)
                .fontWeight(.bold)
                // Tie header routing to the name if there's no active poison banner
                .accessibilityAddTraits(isPoisonous ? [] : .isHeader)
            
            HStack {
                Text(scientificName)
                    .font(.title3)
                    .italic()
                    .foregroundColor(.secondary)
                    
                if let score = inferenceEngine.speciesData?.confidenceScore, score > 0.0 {
                    Text("\(Int(score * 100))% Match")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(score >= 0.85 ? .green : .orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(score >= 0.85 ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            
            if let species = inferenceEngine.speciesData {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if species.isInvasive {
                            BadgeView(text: "Invasive", color: .purple, icon: "exclamationmark.shield.fill")
                        }
                        
                        if !species.isLiveCapture {
                            BadgeView(text: "Not a live capture", color: .gray, icon: "photo.badge.exclamationmark.fill")
                        }
                        
                        if !species.isBiological {
                            BadgeView(text: "Not biological", color: .gray, icon: "xmark.seal.fill")
                        }   
                        
                        if species.ecologyType != "Unknown" {
                            BadgeView(text: species.ecologyType.capitalized, color: .blue, icon: "leaf.fill")
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal)
    }
}

struct InsightDescriptionSection: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    @Binding var isSafariPresented: Bool
    @Binding var selectedWikiURL: URL?
    
    var body: some View {
        if let description = inferenceEngine.speciesData?.insightData.description {
            Text(description)
                .font(.body)
                .padding(.horizontal)
                
            if let rationale = inferenceEngine.speciesData?.insightData.regionalStatusRationale {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Regional context")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    Text(rationale)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
                
            if let wikiString = inferenceEngine.speciesData?.wikipediaUrl, let wikiUrl = URL(string: wikiString) {
                Button(action: {
                    selectedWikiURL = wikiUrl
                    isSafariPresented = true
                }) {
                    HStack {
                        Image(systemName: "safari.fill")
                        Text("Read more on Wikipedia")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .foregroundColor(.primary)
            }
        }
    }
}

struct InsightTaxonomyTree: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    var body: some View {
        if let taxonomy = inferenceEngine.speciesData?.taxonomy {
            VStack(alignment: .leading, spacing: 8) {
                Text("Taxonomy")
                    .font(.headline)
                    .padding(.horizontal)
                    
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        if let kingdom = taxonomy.kingdom { TaxonomyNode(level: "Kingdom", name: kingdom) }
                        if let phylum = taxonomy.phylum { TaxonomyNode(level: "Phylum", name: phylum) }
                        if let cls = taxonomy.className { TaxonomyNode(level: "Class", name: cls) }
                        if let order = taxonomy.order { TaxonomyNode(level: "Order", name: order) }
                        if let family = taxonomy.family { TaxonomyNode(level: "Family", name: family) }
                        if let genus = taxonomy.genus { TaxonomyNode(level: "Genus", name: genus) }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top, 8)
        }
    }
}
