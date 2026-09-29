"""Extract only the final answer from supported model wire formats."""


def final_text(text, output_format="text"):
    if output_format == "text":
        return text
    if output_format != "harmony":
        raise ValueError("Unknown model output format.")
    for header, marker in (("<|start|>assistant", "<|channel|>final<|message|>"),
                           ("<|im_start|>assistant", "<|meta_sep|>final<|im_sep|>")):
        if header + marker in text or text.startswith(marker):
            answer = text.rsplit(header + marker, 1)[1] if header + marker in text else text[len(marker):]
            for ending in ("<|return|>", "<|fim_suffix|>", "<|im_end|>", "<|end|>"):
                if ending in answer:
                    answer = answer.split(ending, 1)[0]
            if answer.strip():
                return answer.strip()
    raise ValueError("The model did not produce a final answer.")
