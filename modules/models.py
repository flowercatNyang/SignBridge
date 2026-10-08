import torch
import torch.nn as nn

class DepthwiseConv1D(nn.Module):
    """
    Lightweight Depthwise Separable 1D Convolution with GroupNorm.
    """
    def __init__(self, in_ch, out_ch, kernel_size=3, padding=1):
        super().__init__()
        # Depthwise
        self.dw = nn.Conv1d(in_ch, in_ch, kernel_size=kernel_size, padding=padding, groups=in_ch, bias=False)
        # Pointwise
        self.pw = nn.Conv1d(in_ch, out_ch, kernel_size=1, bias=False)
        # GroupNorm (using 4 groups, common for small models)
        self.gn = nn.GroupNorm(4, out_ch)
        self.relu = nn.ReLU()

    def forward(self, x):
        return self.relu(self.gn(self.pw(self.dw(x))))

class SignLanguageEncoder(nn.Module):
    """
    Lightweight GRU + Depthwise CNN Encoder for Sign Language Sequences.
    Processes [B, T, 150] sequences into a [B, hidden_dim] embedding.
    """
    def __init__(self, input_dim=150, hidden_dim=64, num_layers=2, dropout_rate=0.5):
        super().__init__()
        # Use Depthwise Convolutions for lighter computation and GroupNorm for better small-batch stability
        self.conv_block = nn.Sequential(
            DepthwiseConv1D(input_dim, 64),
            DepthwiseConv1D(64, 128),
            nn.MaxPool1d(2),
            DepthwiseConv1D(128, 64)
        )
        
        self.gru = nn.GRU(64, hidden_dim, num_layers, batch_first=True, dropout=dropout_rate if num_layers > 1 else 0)
        self.dropout = nn.Dropout(p=dropout_rate)

    def forward(self, x):
        # x is [B, T, C]. Conv1d expects [B, C, T]
        x = x.permute(0, 2, 1)
        x = self.conv_block(x)
        
        # Back to [B, T', C'] for GRU
        x = x.permute(0, 2, 1)
        out, _ = self.gru(x)
        
        # We only need the last timestep output for classification
        last_out = self.dropout(out[:, -1, :])
        return last_out

class SignLanguageModel(nn.Module):
    """
    Complete model combining the Encoder and a single-head Linear classifier.
    """
    def __init__(self, num_classes=112, input_dim=150, hidden_dim=64, num_layers=2):
        super().__init__()
        self.encoder = SignLanguageEncoder(
            input_dim=input_dim, 
            hidden_dim=hidden_dim, 
            num_layers=num_layers
        )
        self.classifier = nn.Linear(hidden_dim, num_classes)
        
    def forward(self, x):
        features = self.encoder(x)
        logits = self.classifier(features)
        return logits
