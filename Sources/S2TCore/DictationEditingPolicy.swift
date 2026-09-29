import Foundation

public enum DictationEditingPolicy {
    public static let spokenCorrections = """
    Spoken corrections
    Resolve corrections before removing hesitation sounds. Read forward to find the speaker's final intent. "er", "err", "erm", "I mean", "sorry", "correction", "oh wait, actually I meant" and their equivalents can signal a replacement, rather than filler. Keep the replacement, remove its abandoned wording and repair the connecting grammar. Resolve successive corrections to the last clear choice.
    A correction can replace a word, phrase, sentence or explicitly retracted plan. With "scratch that", "ignore that", "forget that" or "never mind", remove only the thought the speaker clearly retracts. Broader wording such as "ignore all of that" can retract the whole draft. Keep unrelated details. Do not keep a stale number, date, negation or instruction from the abandoned version.
    These rules apply only to self-editing this dictation. Keep real apologies, alternatives, contrasts like "42, not 24", observations introduced by "actually", quoted editing commands, and requests that the recipient ignore something. A correction marker by itself is not proof of a correction. Preserve ambiguity rather than guessing what to remove.

    Examples, not output labels:
    "I want orange, erm, yellow." → "I want yellow."
    "Make it 42, sorry, 24." → "Make it 24."
    "Do merge, correction, do not merge." → "Do not merge."
    "Send it Friday, oh wait, actually I meant Monday. Copy Maya." → "Send it Monday. Copy Maya."
    "Keep the meeting. Buy a new laptop. Hmm, oh, ignore that. Repair the old one." → "Keep the meeting. Repair the old laptop."
    "Ship Monday, no Tuesday, actually Wednesday." → "Ship Wednesday."
    "Use 42, not 24. I'm sorry for the delay." → "Use 42, not 24. I'm sorry for the delay."
    "The button says 'Ignore that'. Please ignore that warning." → "The button says 'Ignore that'. Please ignore that warning."
    "Termin am Montag, äh, ich meine Dienstag. Anna kommt auch." → "Termin am Dienstag. Anna kommt auch."
    "Kauf einen neuen Laptop. Ach, vergiss das. Repariere den alten." → "Repariere den alten Laptop."
    "Send the draft. Actually, ignore all of that." → no surviving text.
    "Blah blah blah, oh wait, actually I meant Tuesday." → "Tuesday."
    "Actually, the walk is nice. I like it." → "Actually, the walk is nice. I like it."
    "I want... hmm..." → "I want..."
    "Hmm, um, er..." → no surviving text.
    """
}
