"""Finite proposals for the small deployed sign vocabulary. Other input uses the LLM."""

STEPS = {"subject", "notify", "body", "emergency", "hospital", "mother", "message",
         "message_body", "done_on_decline", "llm_proposal"}

def question(step, meaning, prompt):
    return dict(step=step, translation=meaning, question=prompt, action=None)

def proposal(step, meaning, name, **arguments):
    return dict(step=step, translation=meaning, question=None,
                action={"name": name, "arguments": arguments})

def end():
    return dict(translation="요청을 마쳤어요.", question=None, action=None)

def ask_body():
    return question("body", "아픈 부위를 확인하고 있어요.",
                    "어디가 아프세요? 부위를 입력하고 그렇다로 보내거나, 부위를 생략하려면 바로 그렇다로 답해 주세요.")

def emergency():
    return proposal("emergency", "119 전화 화면을 열까요?", "emergency")

def department(words):
    if any(w in words for w in ("위(내장)", "배", "속", "복부")):
        return "내과"
    return "병원"

def guided_plan(data):
    history = data["history"]
    kind, text = data["input_type"], data["text"]
    step = history[-1].get("step") if history else None
    rejected = kind == "rejection"
    confirmed = kind == "confirmation"
    if step == "llm_proposal":
        return None
    if rejected:
        if step == "subject":
            return question("notify", "아픈 사람을 다시 확인할게요.", "내가 아프다는 걸 엄마에게 알리고 싶으세요?")
        if step == "emergency":
            words = " ".join(t["content"] for t in history if t["role"] == "user")
            query = department(words)
            return proposal("hospital", f"이 휴대폰 위치 주변의 {query}를 네이버 지도에서 찾아볼까요?",
                            "nearby_hospital", department=query)
        if step == "mother":
            return question("message", "엄마와 연락하려고 해요.", "엄마에게 문자를 작성할까요?")
        return end()
    if step == "subject" and confirmed:
        return emergency() if department(text) != "병원" else ask_body()
    if step == "notify" and confirmed:
        return proposal("done_on_decline", "엄마에게 ‘나 아파’라는 문자를 작성할까요?",
                        "compose_message", recipient="엄마", body="나 아파.")
    if step == "body":
        return emergency()
    if step == "message" and confirmed:
        return question("message_body", "문자 내용을 입력해 주세요.", "엄마에게 무엇이라고 보낼까요?")
    if step in {"message", "message_body"} and not confirmed:
        return proposal("done_on_decline", "엄마에게 보낼 문안을 확인해 주세요.",
                        "compose_message", recipient="엄마", body=text)
    if step == "message_body" and confirmed:
        return question("message_body", "보낼 내용이 필요해요.", "문자 내용을 입력하고 그렇다로 보내 주세요.")
    if history:
        return None
    if text in ("엄마", "회사"):
        if text == "엄마":
            return proposal("mother", "엄마에게 전화할까요?", "mother")
        return proposal("done_on_decline", "저장한 회사까지 길을 안내할까요?", "company")
    if text in ("위(방향)", "상부", "아래"):
        up = text != "아래"
        return proposal("done_on_decline", "미디어 볼륨을 한 단계 " + ("올릴까요?" if up else "내릴까요?"),
                        "adjust_volume", direction="up" if up else "down")
    tokens = text.split()
    alarm_words = sorted(tokens)
    if alarm_words in (["8", "일어나다"], ["8", "매일매일", "일어나다"]):
        daily = "매일매일" in tokens
        schedule = "매일 오전 8시" if daily else "오전 8시에 한 번"
        return proposal("done_on_decline", f"{schedule} 기상 알람을 설정할까요?",
                        "set_alarm", hour=8, minute=0, label="기상",
                        days=list(range(1, 8)) if daily else [])
    words = set(tokens)
    if "아프다" in words and words <= {"아프다", "엄마", "나", "위(내장)", "배", "속", "복부"}:
        if "엄마" in words:
            if "나" in words:
                return question("notify", "나의 통증과 엄마가 언급됐어요.", "내가 아프다는 걸 엄마에게 알리고 싶으세요?")
            return question("subject", "엄마와 통증이 언급됐어요.", "엄마가 아프시다는 뜻인가요?")
        return emergency() if department(text) != "병원" else ask_body()
    return None
