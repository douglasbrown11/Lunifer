//
//  FeedbackView.swift
//  FeedbackPulse
//
//  Pre-built SwiftUI feedback collection view
//

#if os(iOS)
import SwiftUI
import UIKit

/// A pre-built SwiftUI view for collecting user feedback
@available(iOS 14.0, *)
public struct FeedbackView: View {

    @Environment(\.presentationMode) var presentationMode

    @State private var selectedSentiment: FeedbackSentiment?
    @State private var selectedRatingScore: Int?
    @State private var comment: String = ""
    @State private var isSubmitting: Bool = false
    @State private var showSuccess: Bool = false
    @State private var errorMessage: String?

    /// Customizable title
    public var title: String

    /// Customizable subtitle
    public var subtitle: String

    /// Primary color for the view
    public var primaryColor: Color

    /// Rating type to display (nil = classic sentiment buttons)
    public var ratingType: RatingType?

    /// Callback when feedback is submitted
    public var onSubmit: ((FeedbackSentiment, String?) -> Void)?

    /// Callback when view is dismissed
    public var onDismiss: (() -> Void)?

    public init(
        title: String = "Send us your feedback",
        subtitle: String = "How are you feeling about our app?",
        primaryColor: Color = .green,
        ratingType: RatingType? = nil,
        onSubmit: ((FeedbackSentiment, String?) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.primaryColor = primaryColor
        self.ratingType = ratingType
        self.onSubmit = onSubmit
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top)

                // Rating Selection
                Group {
                    if let ratingType = ratingType {
                        switch ratingType {
                        case .stars:
                            StarRatingView(selectedScore: $selectedRatingScore, primaryColor: primaryColor)
                        case .emoji:
                            EmojiRatingView(selectedScore: $selectedRatingScore)
                        case .nps:
                            NPSRatingView(selectedScore: $selectedRatingScore)
                        case .thumbs:
                            classicSentimentButtons
                        }
                    } else {
                        classicSentimentButtons
                    }
                }
                .padding(.vertical)

                // Comment Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tell us more (optional)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextEditor(text: $comment)
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(8)
                }

                // Error Message
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Spacer()

                // Submit Button
                Button(action: submitFeedback) {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(isSubmitting ? "Sending..." : "Send Feedback")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(!hasNoSelection ? primaryColor : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(hasNoSelection || isSubmitting)

                // Powered by
                Text("Powered by Feedback Pulse")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        onDismiss?()
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .alert("Thank you!", isPresented: $showSuccess) {
                Button("OK") {
                    onDismiss?()
                    presentationMode.wrappedValue.dismiss()
                }
            } message: {
                Text("Your feedback has been submitted successfully.")
            }
        }
    }

    private var hasNoSelection: Bool {
        if ratingType != nil && ratingType != .thumbs {
            return selectedRatingScore == nil
        }
        return selectedSentiment == nil
    }

    @ViewBuilder
    private var classicSentimentButtons: some View {
        HStack(spacing: 20) {
            SentimentButton(
                emoji: "😊",
                label: "Good",
                isSelected: selectedSentiment == .positive,
                color: .green
            ) {
                selectedSentiment = .positive
            }

            SentimentButton(
                emoji: "😐",
                label: "Okay",
                isSelected: selectedSentiment == .neutral,
                color: .yellow
            ) {
                selectedSentiment = .neutral
            }

            SentimentButton(
                emoji: "😞",
                label: "Bad",
                isSelected: selectedSentiment == .negative,
                color: .red
            ) {
                selectedSentiment = .negative
            }
        }
    }

    private func submitFeedback() {
        isSubmitting = true
        errorMessage = nil

        let commentToSend = comment.isEmpty ? nil : comment

        if let ratingType = ratingType, ratingType != .thumbs, let score = selectedRatingScore {
            // Rating type mode
            FeedbackPulse.submit(ratingType: ratingType, ratingScore: score, comment: commentToSend) { result in
                isSubmitting = false
                switch result {
                case .success:
                    // Map score to sentiment for the callback
                    let sentiment: FeedbackSentiment = score <= 2 ? .negative : .positive
                    onSubmit?(sentiment, commentToSend)
                    showSuccess = true
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        } else if let sentiment = selectedSentiment {
            // Classic sentiment mode
            FeedbackPulse.submit(sentiment: sentiment, comment: commentToSend) { result in
                isSubmitting = false
                switch result {
                case .success:
                    onSubmit?(sentiment, commentToSend)
                    showSuccess = true
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Sentiment Button

@available(iOS 14.0, *)
private struct SentimentButton: View {
    let emoji: String
    let label: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 40))

                Text(label)
                    .font(.caption)
                    .foregroundColor(isSelected ? color : .secondary)
            }
            .padding()
            .background(isSelected ? color.opacity(0.15) : Color.clear)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Star Rating View

@available(iOS 14.0, *)
private struct StarRatingView: View {
    @Binding var selectedScore: Int?
    var primaryColor: Color

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { index in
                Button(action: { selectedScore = index }) {
                    Image(systemName: index <= (selectedScore ?? 0) ? "star.fill" : "star")
                        .font(.system(size: 32))
                        .foregroundColor(index <= (selectedScore ?? 0) ? .yellow : .gray.opacity(0.4))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

// MARK: - Emoji Rating View

@available(iOS 14.0, *)
private struct EmojiRatingView: View {
    @Binding var selectedScore: Int?

    private let emojis = [
        (1, "😠", "Terrible"),
        (2, "🙁", "Bad"),
        (3, "😐", "Okay"),
        (4, "🙂", "Good"),
        (5, "🤩", "Amazing")
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(emojis, id: \.0) { score, emoji, label in
                Button(action: { selectedScore = score }) {
                    VStack(spacing: 4) {
                        Text(emoji)
                            .font(.system(size: 32))
                        Text(label)
                            .font(.caption2)
                            .foregroundColor(selectedScore == score ? .primary : .secondary)
                    }
                    .padding(8)
                    .background(selectedScore == score ? Color.blue.opacity(0.15) : Color.clear)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selectedScore == score ? Color.blue : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

// MARK: - NPS Rating View

@available(iOS 14.0, *)
private struct NPSRatingView: View {
    @Binding var selectedScore: Int?

    private func npsColor(for score: Int) -> Color {
        if score <= 6 { return .red }
        if score <= 8 { return .yellow }
        return .green
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0...10, id: \.self) { score in
                    Button(action: { selectedScore = score }) {
                        Text("\(score)")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(selectedScore == score ? npsColor(for: score) : Color(UIColor.systemGray5))
                            .foregroundColor(selectedScore == score ? .white : .primary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            HStack {
                Text("Not likely")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Very likely")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - View Extension

@available(iOS 14.0, *)
public extension View {
    /// Present the FeedbackPulse feedback sheet
    func feedbackSheet(
        isPresented: Binding<Bool>,
        title: String = "Send us your feedback",
        subtitle: String = "How are you feeling about our app?",
        primaryColor: Color = .green,
        ratingType: RatingType? = nil,
        onSubmit: ((FeedbackSentiment, String?) -> Void)? = nil
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            FeedbackView(
                title: title,
                subtitle: subtitle,
                primaryColor: primaryColor,
                ratingType: ratingType,
                onSubmit: onSubmit,
                onDismiss: { isPresented.wrappedValue = false }
            )
        }
    }
}

#endif
