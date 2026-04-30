message SignedMessage {
    publicKey: Int as uint256;
    seqno: Int as uint64;
    validUntil: Int as uint32;
    message: Cell;
    signature: Slice as bytes64;
}

trait SignedExternal with BaseTrait {
    const ErrorInvalidSignature: Int = 2001;
    const ErrorInvalidSeqno: Int = 2002;
    const ErrorCommandExpired: Int = 2003;
    const ErrorUnsupportedSignedMessage: Int = 2004;

    abstract fun checkAuth(msg: SignedMessage);

    abstract fun commitSeqno(msg: SignedMessage);

    abstract fun dispatchSignedMessage(message: Cell);

    virtual fun beforeSignedMessage(_: SignedMessage) {}

    fun signedMessageHash(msg: SignedMessage): Int {
        return beginCell()
            .storeAddress(myAddress())
            .storeUint(msg.publicKey, 256)
            .storeRef(
                beginCell()
                    .storeUint(msg.seqno, 64)
                    .storeUint(msg.validUntil, 32)
                    .storeUint(msg.message.hash(), 256)
                    .endCell(),
            )
            .endCell()
            .hash();
    }

    fun checkSignature(msg: SignedMessage) {
        throwUnless(
            self.ErrorInvalidSignature,
            checkSignature(self.signedMessageHash(msg), msg.signature, msg.publicKey),
        );
    }

    external(msg: SignedMessage) {
        self.checkAuth(msg);
        acceptMessage();
        self.checkSignature(msg);
        self.commitSeqno(msg);
        self.beforeSignedMessage(msg);
        self.dispatchSignedMessage(msg.message);
    }
}
