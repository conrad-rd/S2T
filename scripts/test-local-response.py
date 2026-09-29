"""Protocol fixtures for final-answer extraction, without loading any model."""
import sys
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "Resources/LocalModels"))
from response_text import final_text


class FinalAnswerTests(unittest.TestCase):
    def test_plain_dictation_is_unchanged(self):
        self.assertEqual(final_text("A literal <think> tag."), "A literal <think> tag.")

    def test_converted_harmony_discards_analysis(self):
        raw = "<|channel|>analysis<|message|>Internal work.<|end|><|start|>assistant<|channel|>final<|message|>The cat is sleeping.<|return|>"
        self.assertEqual(final_text(raw, "harmony"), "The cat is sleeping.")

    def test_original_harmony_discards_analysis(self):
        raw = "<|meta_sep|>analysis<|im_sep|>Internal work.<|im_end|><|im_start|>assistant<|meta_sep|>final<|im_sep|>Edited text.<|fim_suffix|>"
        self.assertEqual(final_text(raw, "harmony"), "Edited text.")

    def test_incomplete_reasoning_is_never_delivered(self):
        with self.assertRaises(ValueError):
            final_text("<|channel|>analysis<|message|>Unfinished work", "harmony")

    def test_final_marker_inside_analysis_is_not_an_answer(self):
        with self.assertRaises(ValueError):
            final_text("<|channel|>analysis<|message|>Mention <|channel|>final<|message|> as an example.", "harmony")

    def test_empty_final_is_rejected(self):
        with self.assertRaises(ValueError):
            final_text("<|channel|>final<|message|><|return|>", "harmony")


if __name__ == "__main__":
    unittest.main()
