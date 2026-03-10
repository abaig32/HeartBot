import streamlit as st
from api import query_heartbot, format_citations
from config import APP_TITLE, APP_DESCRIPTION

st.set_page_config(
    page_title=APP_TITLE,
    layout="centered"
)

st.title(f"{APP_TITLE}")
st.caption(f"{APP_DESCRIPTION}")
st.warning("This chatbot is for informational purposes only and does not replace professional medical advice or diagnosis!")
st.divider()

if "messages" not in st.session_state:
    st.session_state.messages = []

for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])
        if message.get("sources"):
            with st.expander("sources"):
                for source in message["sources"]:
                    st.write(source)

if prompt := st.chat_input("Ask about heart health and symptoms!"):
    with st.chat_message("user"):
        st.markdown(prompt)
    st.session_state.messages.append({"role": "user", "content": prompt})
    
    with st.chat_message("assistant"):
        with st.spinner("Responding..."):
            result = query_heartbot(prompt)
        
        if "error" in result:
            response = f"{result['error']}"
            sources = []
        else:
            response = result.get("answer", "I could not find an answer.")
            sources = format_citations(result.get("citations", []))

        st.markdown(response)

        if sources:
            with st.expander("Sources"):
                for source in sources:
                    st.wrtie(sources)
        
        st.session_state.messages.append({"role": "assistant", "content": response, "sources": sources})


#RUN WITH streamlit run app.py